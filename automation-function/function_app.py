import azure.functions as func
import logging
import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

@app.route(route="remediation_trigger", methods=["POST"])
def remediation_trigger(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Azure Monitor Alert Webhook received.")
    
    try:
        req_body = req.get_json()
        # Extracts the exact resource ID of whichever VM broke from the common alert schema payload
        target_resource_id = req_body['data']['alertContext']['resourceId']
        vm_name = target_resource_id.split('/')[-1]
        resource_group = target_resource_id.split('/')[4]
        subscription_id = target_resource_id.split('/')[2]
        
        logging.info(f"Targeting broken VM: {vm_name} inside group: {resource_group}")

        # Authenticates seamlessly using the System-Assigned Managed Identity
        credential = DefaultAzureCredential()
        compute_client = ComputeManagementClient(credential, subscription_id)

        # Triggers the host execution command securely
        poller = compute_client.virtual_machines.begin_run_command(
            resource_group_name=resource_group,
            vm_name=vm_name,
            parameters={
                "commandId": "RunShellScript",
                "script": ["docker restart flask-app"]
            }
        )
        poller.result()
        
        return func.HttpResponse(f"Successfully restarted container on {vm_name}.", status_code=200)
    except Exception as e:
        logging.error(f"Execution failed: {str(e)}")
        return func.HttpResponse(f"Error executing remediation: {str(e)}", status_code=500)