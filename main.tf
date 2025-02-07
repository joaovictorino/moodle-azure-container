terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.2"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-moodle-experimentacao"
    storage_account_name = "saterraformstatemoodle"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  type = string
}

data "azurerm_resource_group" "rg-moodle-experimentacao" {
  name = "rg-moodle-experimentacao"
}

resource "azurerm_virtual_network" "vnet-moodle" {
  name                = "vnet-moodle"
  location            = data.azurerm_resource_group.rg-moodle-experimentacao.location
  resource_group_name = data.azurerm_resource_group.rg-moodle-experimentacao.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "snet-container-apps" {
  name                 = "snet-container-apps"
  resource_group_name  = data.azurerm_resource_group.rg-moodle-experimentacao.name
  virtual_network_name = azurerm_virtual_network.vnet-moodle.name
  address_prefixes     = ["10.0.0.0/23"]
}

resource "azurerm_subnet" "snet-mysql" {
  name                 = "snet-mysql"
  resource_group_name  = data.azurerm_resource_group.rg-moodle-experimentacao.name
  virtual_network_name = azurerm_virtual_network.vnet-moodle.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "dns-mysql" {
  name                = "moodle.mysql.database.azure.com"
  resource_group_name = data.azurerm_resource_group.rg-moodle-experimentacao.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns-mysql-link" {
  name                  = "mysql-dns-link"
  resource_group_name   = data.azurerm_resource_group.rg-moodle-experimentacao.name
  private_dns_zone_name = azurerm_private_dns_zone.dns-mysql.name
  virtual_network_id    = azurerm_virtual_network.vnet-moodle.id
  registration_enabled  = false
}

resource "azurerm_log_analytics_workspace" "logs-moodle" {
  name                = "logs-moodle"
  location            = data.azurerm_resource_group.rg-moodle-experimentacao.location
  resource_group_name = data.azurerm_resource_group.rg-moodle-experimentacao.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "env-moodle" {
  name                       = "env-moodle"
  location                   = data.azurerm_resource_group.rg-moodle-experimentacao.location
  resource_group_name        = data.azurerm_resource_group.rg-moodle-experimentacao.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs-moodle.id
  infrastructure_subnet_id   = azurerm_subnet.snet-container-apps.id
}

resource "azurerm_mysql_flexible_server" "srv-mysql-moodle" {
  name                   = "srv-mysql-moodle"
  resource_group_name    = data.azurerm_resource_group.rg-moodle-experimentacao.name
  location               = data.azurerm_resource_group.rg-moodle-experimentacao.location
  administrator_login    = "moodleadmin"
  administrator_password = "Change_This_Password_123!"
  sku_name               = "B_Standard_B1s"
  version                = "8.0.21"
  zone                   = "1"

  delegated_subnet_id = azurerm_subnet.snet-mysql.id
  private_dns_zone_id = azurerm_private_dns_zone.dns-mysql.id

  storage {
    size_gb = 20
  }
}

resource "azurerm_mysql_flexible_database" "moodledb" {
  name                = "moodledb"
  resource_group_name = data.azurerm_resource_group.rg-moodle-experimentacao.name
  server_name         = azurerm_mysql_flexible_server.srv-mysql-moodle.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

resource "azurerm_mysql_flexible_server_configuration" "disable_secure_transport" {
  name                = "require_secure_transport"
  resource_group_name = data.azurerm_resource_group.rg-moodle-experimentacao.name
  server_name         = azurerm_mysql_flexible_server.srv-mysql-moodle.name
  value               = "OFF"
}

resource "random_string" "random" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "sa-moodle" {
  name                     = "moodleexperiment${random_string.random.result}"
  resource_group_name      = data.azurerm_resource_group.rg-moodle-experimentacao.name
  location                 = data.azurerm_resource_group.rg-moodle-experimentacao.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_share" "sa-share-moodle" {
  name               = "moodle"
  storage_account_id = azurerm_storage_account.sa-moodle.id
  quota              = 50
}

resource "azurerm_storage_share" "sa-share-moodledata" {
  name               = "moodledata"
  storage_account_id = azurerm_storage_account.sa-moodle.id
  quota              = 50
}

resource "azurerm_container_app_environment_storage" "env-storage-moodle" {
  name                         = "env-storage-moodle"
  container_app_environment_id = azurerm_container_app_environment.env-moodle.id
  account_name                 = azurerm_storage_account.sa-moodle.name
  share_name                   = azurerm_storage_share.sa-share-moodle.name
  access_key                   = azurerm_storage_account.sa-moodle.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app" "moodle-job" {
  name                         = "moodle-job"
  container_app_environment_id = azurerm_container_app_environment.env-moodle.id
  resource_group_name          = data.azurerm_resource_group.rg-moodle-experimentacao.name
  revision_mode                = "Single"

  template {
    min_replicas = 1
    max_replicas = 1
    container {
      name   = "moodle"
      image  = "bitnami/moodle:4.5.1-debian-12-r3"
      cpu    = 2.0
      memory = "4Gi"

      env {
        name  = "BITNAMI_DEBUG"
        value = true
      }

      env {
        name  = "PHP_MEMORY_LIMIT"
        value = "512M"
      }

      env {
        name  = "APACHE_LOG_LEVEL"
        value = "debug"
      }

      env {
        name  = "MOODLE_DATABASE_HOST"
        value = azurerm_mysql_flexible_server.srv-mysql-moodle.fqdn
      }

      env {
        name  = "MOODLE_DATABASE_TYPE"
        value = "mysqli"
      }

      env {
        name  = "MOODLE_DATABASE_PORT_NUMBER"
        value = "3306"
      }

      env {
        name  = "MOODLE_DATABASE_USER"
        value = azurerm_mysql_flexible_server.srv-mysql-moodle.administrator_login
      }

      env {
        name  = "MOODLE_DATABASE_PASSWORD"
        value = azurerm_mysql_flexible_server.srv-mysql-moodle.administrator_password
      }

      env {
        name  = "MOODLE_DATABASE_NAME"
        value = azurerm_mysql_flexible_database.moodledb.name
      }

      volume_mounts {
        name = "moodle"
        path = "/moodle"
      }

      volume_mounts {
        name = "moodledata"
        path = "/moodledata"
      }

    }

    volume {
      name         = "moodle"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.env-storage-moodle.name
    }

    volume {
      name         = "moodledata"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.env-storage-moodle.name
    }

  }
}

resource "azurerm_container_app" "moodle" {
  name                         = "moodle-app"
  container_app_environment_id = azurerm_container_app_environment.env-moodle.id
  resource_group_name          = data.azurerm_resource_group.rg-moodle-experimentacao.name
  revision_mode                = "Single"

  template {
    min_replicas = 1
    max_replicas = 2
    container {
      name   = "moodle"
      image  = "bitnami/moodle:4.5.1-debian-12-r3"
      cpu    = 2.0
      memory = "4Gi"

      env {
        name  = "BITNAMI_DEBUG"
        value = true
      }

      env {
        name  = "MOODLE_SKIP_BOOTSTRAP"
        value = "yes"
      }

      env {
        name  = "PHP_MEMORY_LIMIT"
        value = "512M"
      }

      env {
        name  = "APACHE_LOG_LEVEL"
        value = "debug"
      }

      env {
        name  = "MOODLE_DATABASE_HOST"
        value = azurerm_mysql_flexible_server.srv-mysql-moodle.fqdn
      }

      env {
        name  = "MOODLE_DATABASE_TYPE"
        value = "mysqli"
      }

      env {
        name  = "MOODLE_DATABASE_PORT_NUMBER"
        value = "3306"
      }

      env {
        name  = "MOODLE_DATABASE_USER"
        value = azurerm_mysql_flexible_server.srv-mysql-moodle.administrator_login
      }

      env {
        name  = "MOODLE_DATABASE_PASSWORD"
        value = azurerm_mysql_flexible_server.srv-mysql-moodle.administrator_password
      }

      env {
        name  = "MOODLE_DATABASE_NAME"
        value = azurerm_mysql_flexible_database.moodledb.name
      }

      volume_mounts {
        name = "moodle"
        path = "/moodle"
      }

      volume_mounts {
        name = "moodledata"
        path = "/moodledata"
      }

    }

    volume {
      name         = "moodle"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.env-storage-moodle.name
    }

    volume {
      name         = "moodledata"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.env-storage-moodle.name
    }

  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

output "moodle_url" {
  value = "https://${azurerm_container_app.moodle.latest_revision_fqdn}"
}

