# AWS Serverless Architecture with Terraform

## Resumo


Esse projeto explora o uso do terraform Infraestructure as Code (Iac), com providers aws na versao
6.68.0 usando IAM role, policys, filas queue e DLQ como tambem api gateway/lambda e RDS

Utilizei este codigo para praticar com a sintaxe do terraform, é um codigo ficticio apartir da documentacao do provider AWS.



## Arquitetura

1. **Amazon API Gateway (HTTP API):** 
2. **AWS Lambda (Producer):** 
3. **Amazon SQS:** 
4. **AWS Lambda (Consumer):** 
5. **Amazon RDS for MySQL:** 

A configuracao da fila SQS inclue a Dead Letter queue (DLQ) 

## AWS Services

- **Amazon API Gateway:** 
- **AWS Lambda:** 
- **Amazon SQS:** 
- **Amazon SQS Queue Policy:** 
- **Amazon SQS Dead Letter Queue:** 
- **AWS IAM:** 
- **Amazon RDS for MySQL:**
- **Terraform AWS Provider:** 

## Tecnologias

- Terraform 1.7.6
- AWS Provider 6.68.0
- HCL (HashiCorp Configuration Language)
- AWS serverless and database services

## Estrutura do projeto

```text
terraform-api/
├── main.tf
├── README.md
└── .gitignore
```

packages adicionais caso necessario:

```text
function.zip
consumer.zip
```
