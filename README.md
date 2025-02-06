# Terraform do ambiente de Moodle utilizando Azure MySQL Flexible Server e Azure Container Apps

Pré-requisitos

- Az-cli instalado
- Terraform instalado

Logar no Azure via az-cli, o navegador será aberto para que o login seja feito

```sh
az login
```

Inicializar o Terraform

```sh
terraform init
```

Executar o Terraform

```sh
terraform apply -auto-approve
```

Após migration o container de job não é mais necessário, então basta excluir com o comando abaixo

```sh
terraform destroy --target azurerm_container_app.moodle-job
```
