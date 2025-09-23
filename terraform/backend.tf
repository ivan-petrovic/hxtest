terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstatestorage82063e34"
    container_name       = "hxtest"
    key                  = "terraform.tfstate"
  }
}
