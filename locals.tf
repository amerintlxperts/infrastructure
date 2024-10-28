locals {
  vm-image = {
    "fortiweb" = {
      publisher = "fortinet"
      offer     = "fortinet_fortiweb-vm_v5"
      size      = "Standard_F16s_v2"
      size-dev  = "Standard_F16s_v2"
      version   = "latest"
      #sku             = "fortinet_fw-vm_payg_v3"
      sku = "fortinet_fw-vm_payg_v2"
      #sku = "fortinet_fw-vm"
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
      #size = "Standard_B2ms"
      #size      = "Standard_E4s_v3"
      #gpu-size  = "Standard_NC6s_v3" #16GB
      gpu-size = "Standard_NC24s_v3"
      #gpu-size      = "Standard_NC4as_T4_v3" # 16GB
      #gpu-size      = "Standard_ND40rs_v2" # 32 GB vlink
      #gpu-size      = "Standard_NC24ads_A100_v4" # 80GB - not supported by azure-linux
    }
  }
}
