import json, logging, os, time, boto3, gzip, urllib.parse
from io import BytesIO; from botocore.exceptions import ClientError
logger = logging.getLogger(); log_level = os.environ.get('LOG_LEVEL', 'INFO').upper(); logger.setLevel(log_level if log_level in ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'] else 'INFO')
sns_topic_arn = os.environ.get('SNS_TOPIC_ARN'); dest_log_group_name = os.environ.get('DESTINATION_LOG_GROUP_NAME')
s3_client = boto3.client('s3'); sns_client = boto3.client('sns'); logs_client = boto3.client('logs')
MAX_SNS_SUBJECT_LENGTH = 100; MAX_SNS_MESSAGE_LENGTH = 256 * 1024; MAX_CW_LOG_EVENT_SIZE = 262144 - 26; MAX_CW_BATCH_SIZE = 1048576; MAX_CW_BATCH_COUNT = 10000
def format_sns_message(subject, body): truncated_subject = subject[:MAX_SNS_SUBJECT_LENGTH]; truncated_body = body; return truncated_subject, truncated_body
def create_log_stream_if_needed(log_group_name, log_stream_name):
    try: logs_client.create_log_stream(logGroupName=log_group_name, logStreamName=log_stream_name); logger.info(f"Criado log stream: {log_stream_name} em {log_group_name}"); return None
    except logs_client.exceptions.ResourceAlreadyExistsException: logger.debug(f"Log stream {log_stream_name} ja existe."); return None
    except ClientError as e: logger.error(f"Erro ao criar log stream {log_stream_name}: {e}"); raise
def put_logs_with_retry(log_group_name, log_stream_name, log_events, sequence_token):
    try:
        kwargs = {'logGroupName': log_group_name, 'logStreamName': log_stream_name, 'logEvents': log_events}
        if sequence_token: kwargs['sequenceToken'] = sequence_token
        response = logs_client.put_log_events(**kwargs); return response.get('nextSequenceToken')
    except (logs_client.exceptions.InvalidSequenceTokenException, logs_client.exceptions.DataAlreadyAcceptedException) as e:
        logger.warning(f"Token invalido/dados ja aceitos para {log_stream_name}. Obtendo novo token: {e}")
        expected_token = None
        if hasattr(e, 'response') and 'Error' in e.response and 'Message' in e.response['Error']:
            try: expected_token = e.response['Error']['Message'].split(':')[-1].strip()
            except Exception: pass
        if expected_token and expected_token != 'null':
            logger.info(f"Reenviando com token esperado: {expected_token}"); kwargs['sequenceToken'] = expected_token
            try: response = logs_client.put_log_events(**kwargs); logger.info("Reenvio com token esperado bem-sucedido."); return response.get('nextSequenceToken')
            except Exception as retry_e: logger.error(f"Erro no reenvio com token esperado: {retry_e}"); raise
        else:
             logger.warning("Nao foi possivel extrair token da msg, descrevendo stream...");
             try:
                 streams = logs_client.describe_log_streams(logGroupName=log_group_name, logStreamNamePrefix=log_stream_name, limit=1)
                 if streams.get('logStreams'):
                      token = streams['logStreams'][0].get('uploadSequenceToken')
                      if token: kwargs['sequenceToken'] = token; response = logs_client.put_log_events(**kwargs); logger.info("Reenvio com token descrito bem-sucedido."); return response.get('nextSequenceToken')
                 logger.error(f"Nao foi possivel obter token descrevendo stream {log_stream_name}.")
                 raise e
             except Exception as desc_e: logger.error(f"Erro ao descrever stream no reenvio: {desc_e}"); raise e
    except Exception as e: logger.error(f"Erro inesperado ao enviar logs para {log_stream_name}: {e}"); raise
def process_s3_object(bucket_name, object_key, event_time):
    try:
        response = s3_client.get_object(Bucket=bucket_name, Key=object_key); body = response['Body']; lines = []
        if object_key.endswith('.gz'):
            with gzip.GzipFile(fileobj=BytesIO(body.read())) as f: lines = [line.decode('utf-8', errors='ignore') for line in f]
        else: lines = [line.decode('utf-8', errors='ignore') for line in body.iter_lines()]
        if not lines: logger.info(f"Objeto S3 vazio: s3://{bucket_name}/{object_key}"); return 0
        stream_name_base = ''.join(c if c.isalnum() or c in '-_.' else '_' for c in object_key); log_stream_name = f"{stream_name_base[:150]}-{event_time.replace(':','-').replace('T','_').replace('Z','')}"[:512]
        if not dest_log_group_name: logger.error("DESTINATION_LOG_GROUP_NAME nao definido!"); return -1
        current_token = create_log_stream_if_needed(dest_log_group_name, log_stream_name); log_batch = []; current_batch_size = 0; total_lines_sent = 0; timestamp = int(time.time() * 1000)
        for line in lines:
            line_utf8 = line.encode('utf-8'); line_size = len(line_utf8)
            if line_size > MAX_CW_LOG_EVENT_SIZE: line = line[:MAX_CW_LOG_EVENT_SIZE // 4] + "... [TRUNCADO]"; line_utf8 = line.encode('utf-8'); line_size = len(line_utf8)
            event = {'timestamp': timestamp, 'message': line}; event_size_overhead = line_size + 26
            if not log_batch or (len(log_batch) < MAX_CW_BATCH_COUNT and current_batch_size + event_size_overhead <= MAX_CW_BATCH_SIZE): log_batch.append(event); current_batch_size += event_size_overhead
            else: current_token = put_logs_with_retry(dest_log_group_name, log_stream_name, log_batch, current_token); total_lines_sent += len(log_batch); log_batch = [event]; current_batch_size = event_size_overhead
        if log_batch: current_token = put_logs_with_retry(dest_log_group_name, log_stream_name, log_batch, current_token); total_lines_sent += len(log_batch)
        return total_lines_sent
    except Exception as e: logger.exception(f"Erro ao processar objeto S3 s3://{bucket_name}/{object_key}"); raise
def lambda_handler(event, context):
    logger.info(f"Recebido evento SNS: {json.dumps(event, indent=2)}"); published_count = 0; processed_records = 0; total_lines_to_cw = 0; error_count = 0
    if not sns_topic_arn: logger.critical("SNS_TOPIC_ARN nao configurado!"); raise ValueError("SNS_TOPIC_ARN ausente.")
    if not dest_log_group_name: logger.critical("DESTINATION_LOG_GROUP_NAME nao configurado!"); raise ValueError("DESTINATION_LOG_GROUP_NAME ausente.")
    for sns_record in event.get('Records', []):
        try:
            message_str = sns_record.get('Sns', {}).get('Message'); s3_event = json.loads(message_str)
            for s3_record in s3_event.get('Records', []):
                processed_records += 1; bucket_name = s3_record['s3']['bucket']['name']; object_key = urllib.parse.unquote_plus(s3_record['s3']['object']['key'], encoding='utf-8'); object_size = s3_record['s3']['object'].get('size', 0); event_time = s3_record.get('eventTime', 'N/A')
                if not bucket_name or not object_key: logger.warning("Registro S3 invalido."); error_count += 1; continue
                lines_sent = -1
                try: lines_sent = process_s3_object(bucket_name, object_key, event_time)
                except Exception as cw_err: logger.error(f"Falha ao enviar logs para CW para {object_key}: {cw_err}"); error_count += 1
                if lines_sent >= 0: total_lines_to_cw += lines_sent
                subject = f"Log S3 Recebido: {object_key}"; message = f"Objeto S3 criado:\nBucket: {bucket_name}\nChave: {object_key}\nTamanho: {object_size} bytes\nHora: {event_time}\nLinhas p/ CW: {lines_sent}\nReq ID: {context.aws_request_id}"; final_subject, final_message = format_sns_message(subject, message)
                try: sns_response = sns_client.publish(TopicArn=sns_topic_arn, Subject=final_subject, Message=final_message); logger.info(f"Notificacao SNS enviada para {object_key}. MsgId: {sns_response.get('MessageId')}"); published_count += 1
                except Exception as sns_err: logger.exception(f"Falha ao enviar SNS para {object_key}: {sns_err}"); error_count += 1
        except Exception as e: logger.exception(f"Erro critico processando registro SNS: {json.dumps(sns_record)}"); error_count += 1
    summary_msg = f"Processados {processed_records} registros S3. Notificacoes SNS: {published_count}. Linhas para CW: {total_lines_to_cw}. Erros: {error_count}."
    logger.info(summary_msg); return {'statusCode': 200, 'body': json.dumps(summary_msg)}
