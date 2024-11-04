locals {
  vm-image = {
    "fortiweb" = {
      publisher = "fortinet"
      offer     = "fortinet_fortiweb-vm_v5"
      size      = "Standard_F16s_v2"
      size-dev  = "Standard_D3_v2"
      version   = "latest"
      #sku             = "fortinet_fw-vm_payg_v3"
      sku             = "fortinet_fw-vm_payg_v2"
      management-port = "8443"
      terms           = true
    },
    "aks" = {
      version   = "latest"
      terms     = false
      offer     = ""
      sku       = ""
      publisher = ""
      size      = "Standard_E4s_v3"
      size-dev  = "Standard_B8ms"
      #size-dev = "Standard_B2ms"
      gpu-size     = "Standard_NC24s_v3"
      gpu-size-dev = "Standard_NC4as_T4_v3"
      #gpu-size  = "Standard_NC6s_v3" #16GB
    }
  }
}
