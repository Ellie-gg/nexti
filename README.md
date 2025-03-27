
Este repositório contém código Terraform para provisionar uma infraestrutura na AWS, com a finalidade de atender ao desafio técnico proposto pela NexTi

Pré-requisitos:
Registro de um domínio na conta aws. Pelo route53, foi criado na minha conta pessoal o domínio elielnexti.click. Para rodar a aplicação esse valor deverá ser alterado nas variáveis.
* **Domínio Base:** elielnexti.click
* **URL da aplicação:** `http://dev-app.elielnexti.click`
* Bucket para state do terraform. Foi criado o bucket nexti-tfstate e o lock atráves do DynamoDB
* **Estado Terraform:** Backend S3 (`nexti-tfstate`) e Lock DynamoDB (`tabelalock`).
**Terraform CLI instalado (>= 1.3.0).**



Instruções

  **Variáveis:** Revise o arquivo variables.tf e altere as variáveis conforme seu ambiente.
  
  **PROTEJA A SENHA DO DB:** Crie `terraform.tfvars` com `db_password = "..."`.
  
  **Inicialize:** `terraform init -reconfigure`
  
  **Selecione/Crie o Workspace:** `terraform workspace select dev || terraform workspace new dev`
  
  **Valide e Formate:** `terraform fmt -recursive && terraform validate`
 
  **Planeje:** `terraform plan`
 
 **Aplique:** `terraform apply` (Confirme com `yes`)
 
 **Confirme Assinaturas SNS:** Verifique o e-mail `eliel.garcia@gmail.com`.
 
 **DELEGAÇÃO DNS:** Use os valores do output `route53_name_servers` para atualizar os NS do seu domínio `elielnexti.click`. (Alterar no arquivo de variaveis para seu domínio)
 
 **Acesse:** Após a propagação do DNS, acesse `http://dev-app.elielnexti.click`.


## Destruindo


terraform destroy

Sugestões de Melhorias Futuras:

Gerenciar secrets com AWS Secrets Manager.
Refinar políticas IAM para seguir o princípio de menor privilégio.
Restringir regras de saída (egress) nos Security Groups e Network ACLs.
Implementar HTTPS no Load Balancer com certificado.

Criar mais módulos Terraform IAM separados.
Adicionar blocos validation às variáveis de entrada.
Integrar terraform fmt, tflint, checkov/tfsec em CI/CD.

Implementar testes de integração com Terratest em um ambiente dedicado.
Adicionar testes end-to-end que validem a aplicação na infraestrutura provisionada.
Usar ferramentas como Infracost para análise de custos no planejamento.

Melhorar a configuração do CloudWatch Agent para logs de aplicação.
Instrumentar o código da aplicação para enviar dados ao X-Ray.
Implementar a lógica real de parsing e resumo na Função Lambda.
Criar alarme de tamanho do bucket S3

