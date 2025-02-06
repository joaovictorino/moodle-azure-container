terraform init

terraform validate

terraform fmt

terraform plan

terraform apply

# After migrating MySQL database
terraform destroy --target azurerm_container_app.moodle-job

# Recreate site when necessary
terraform destroy --target azurerm_container_app.moodle-app
