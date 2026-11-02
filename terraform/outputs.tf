output "vm_id" {
  description = "Resource ID of the created virtual machine."
  value       = azurerm_linux_virtual_machine.vm.id
}

output "private_ip_address" {
  description = "Static private IP address assigned to the VM's NIC."
  value       = azurerm_network_interface.vm.private_ip_address
}
