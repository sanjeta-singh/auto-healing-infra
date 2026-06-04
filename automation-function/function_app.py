import azure.functions as func
import logging
import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

@app.route(route="remediation_trigger", methods=["POST"])
def remediation_trigger(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request.")
    
    vm_name = os.environ.get("TARGET_VM_NAME")
    resource_group = os.environ.get("TARGET_RESOURCE_GROUP")
    subscription_id = os.environ.get("TARGET_SUBSCRIPTION_ID")
    
    try:
        credential = DefaultAzureCredential()
        compute_client = ComputeManagementClient(credential, subscription_id)

        # Corrected syntax for RunShellScript
        poller = compute_client.virtual_machines.begin_run_command(
            resource_group_name=resource_group,
            vm_name=vm_name,
            parameters={
                "command_id": "RunShellScript",
                "script": ["docker restart flask-app"]
            }
        )
        poller.result()
        
        return func.HttpResponse(f"Successfully sent restart command to {vm_name}.", status_code=200)
    
    except Exception as e:
        logging.error(f"CRITICAL ERROR: {str(e)}")
        return func.HttpResponse(f"Failed: {str(e)}", status_code=500)