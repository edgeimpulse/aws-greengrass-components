# Edge Impulse with AWS IoT Greengrass

AWS IoT Greengrass is an AWS IoT service that enables edge devices with customizable/downloadable/installable "components" that can be run to augment what's running on the edge device itself.  AWS IoT Greengrass permits the creation and publication of a "Greengrass Component" that is effectively a set of instructions and artifacts that, when installed and run, create and initiate a custom specified service. [AWS IoT Greengrass](https://docs.aws.amazon.com/greengrass/v2/developerguide/what-is-iot-greengrass.html)

Edge Impulse as several services that can be run on the edge device for several purposes outlined below.

#### edge-impulse-linux service ("EdgeImpulseLinuxServiceComponent" GG Component)

The "edge-impulse-linux-service" allows a linux-based edge device to register itself to the Edge Impulse studio service as a device capable of relaying its sensory (typically, camera, microphone, etc...) to the Edge Impulse service to be used for data creation and model testing. The associated GG component for this service allows for easy/scalable deployment of this service to edge devices. 

######Note: This component will attempt to capture camera devices so typically it cannot be installed in the same edge device that has the "edge-impulse-linux-runner" component (described below) at the same time. 

#### edge-impulse-linux-runner service ("EdgeImpulseLinuxRunnerServiceComponent" GG Component)

The "edge-impulse-linux-runner" service downloads, configures, installs, and executes an Edge Impulse model, developed for the specific edge device, and provides the ability to retrieve model inference results.  In this case, our component for this service will relay the inference results into AWS IoTCore under the following topic:

		/edgeimpulse/device/<Device>/inference/output
		
######Note: This component will attempt to capture camera devices so typically it cannot be installed in the same edge device that has the "edge-impulse-linux-runner" component (described prior) at the same time. 

#### edge-impulse-run-impulse service ("EdgeImpulseSerialRunnerServiceComponent" GG Component)

The "edge-impulse-run-impulse" service is typically used when you want to utilize a MCU-based device to run the Edge Impulse model and you further want that device tethered to an edge device via serial/usb connections to allow its inference results to be relayed upstream.  Like with the "edge-impulse-linux-runner" service, the "edge-impulse-run-impulse" component will relay inference results into AWS IoTCore via the same topic structure:

		/edgeimpulse/device/<Device>/inference/output

## Installation

The following sections outline how one installs AWS IoT Greengrass... then installs the Edge Impulse custom components for inclusion into a Greengrass deployment down to edge devices. 

### 1. Install AWS IoT Greengrass Prerequisites

AWS IoT Greengrass is based on Java and thus a Java runtime must be installed. For most linux-based devices a suitable Java can be run by simply typing:

	Debian-based Linux:

			% sudo apt install -y default-jdk

	Redhat-based Linux: 

			% sudo yum install -y default-jdk

Additionally, its recommended to update your linux device with the latest security patches and updates if available. 

### 2. Install AWS IoT Greengrass

Greengrass is typically installed from within the AWS Console -> AWS IoTCore -> Greengrass -> Core Devices menu... select/press "Set up one core device":

![CreateDevice](/.gitbook/assets/GG_Install_Device.png)

### 3. Install defaulted AWS IoT Greengrass components

It is recommended that you create a Deployment in GG for your newly added Greengrass edge device and add the following available AWS Components:

			aws.greengrass.Cli
			aws.greengrass.Nucleus
			aws.greengrass.TokenExchangeService
			aws.greengrass.clientdevices.Auth
			aws.greengrass.clientdevices.IPDetector

### 4. Clone the repo to acquire the Edge Impulse Component recipes and artifacts

Clone this repo to retrieve the Edge Impulse component recipies (yaml files) and the associated artifacts: [Repo](https://github.com/edgeimpulse/edgeimpulse).  You will find the artifacts located in the "AWSGreengrassComponents" directory there. 

### 5. Upload Edge Impulse Greengrass Component artifacts into AWS S3

First, you need to go to the S3 console in AWS via AWS Console -> S3. From there, you will create an S3 bucket.  For sake of example, we name this bucket "MyS3Bucket123".  

Next, the following directory structure needs to be created your new bucket:

		./artifacts/EdgeImpulseServiceComponent/1.0.0
		
Next, navigate to the "1.0.0" directory in your S3 bucket and then press "Upload" to upload the artifacts into the bucket. You need to upload the following files (these will be located in the ./artifacts/EdgeImpulseServiceComponent/1.0.0 from your cloned repo starting in the "AWSGreengrassComponents" subdirectory). Please upload ALL of these files into S3 at the above directory location:

		aws-iotcore-connector.ts	
		launch.sh			
		run.sh
		aws-iotcore-serial-scraper.ts	
		launch_serial.sh		
		run_serial.sh
		install.sh		
		package.json			
		stop.sh
		install_serial.sh		
		parser.sh
		
### 6. Customize the component recipe files

Next we need to customize our GG component recipe files to reflect the actual location of our artifacts stored in S3.  Please replace ALL occurances of "mys3repo123987" with your S3 bucket name (i.e. "MyS3Bucket123"). Please do this for each of the 3 yaml files you have in your cloned repo under "./AWSGreengrassComponents". 

Additionally, we can customize the defaulted configuration of your custom component by  editing, within each yaml file, the default configuration JSON.  Each yaml file's JSON is DIFFERENT... so don't edit one then copy to the other 2 yaml files... that will break your components.  You must edit each yaml file separately without copy/paste of this json information. 

The default configuration contains the following attributes:

	EdgeImpulseLinuxServiceComponent.yaml:
	{
	      "node_version": "20.12.1",		             
	      "vips_version": "8.12.1",                    
	      "device_name": "MyEdgeImpulseDevice",
	      "launch": "linux",
	      "sleep_time_sec": 10,
	      "lock_filename": "/tmp/ei_lockfile_linux",
	      "gst_args": "__none__",
	      "eiparams": "--greengrass",
	      "iotcore_backoff": "5",
	      "iotcore_qos": "1",
	      "ei_bindir": "/usr/local/bin",
	      "ei_sm_secret_id": "EI_API_KEY",
	      "ei_sm_secret_name": "ei_api_key",
	      "ei_ggc_user_groups": "video audio input users",
	      "install_kvssink": "no",
      	      "publish_inference_base64_image": "no",
      	      "enable_cache_to_file": "no",
      	      "cache_file_directory": "__none__"
    	}
    	
    	EdgeImpulseLinuxRunnerServiceComponent.yaml:
    	{
	      "node_version": "20.12.1",
	      "vips_version": "8.12.1",
	      "device_name": "MyEdgeImpulseDevice",
	      "launch": "runner",
	      "sleep_time_sec": 10,
	      "lock_filename": "/tmp/ei_lockfile_runner",
	      "gst_args": "__none__",
	      "eiparams": "--greengrass",
	      "iotcore_backoff": "5",
	      "iotcore_qos": "1",
	      "ei_bindir": "/usr/local/bin",
	      "ei_sm_secret_id": "EI_API_KEY",
	      "ei_sm_secret_name": "ei_api_key",
	      "ei_ggc_user_groups": "video audio input users",
              "install_kvssink": "no",
              "publish_inference_base64_image": "no",
              "enable_cache_to_file": "no",
              "cache_file_directory": "__none__"
   	 }
    	
    	EdgeImpulseSerialRunnerServiceComponent.yaml:
	{
	      "node_version": "20.12.1",
	      "device_name": "MyEdgeImpulseDevice",
	      "sleep_time_sec": 10,
	      "lock_filename": "/tmp/ei_lockfile_serial_runner",
	      "iotcore_backoff": "5",
	      "iotcore_qos": "1",
	      "ei_bindir": "/usr/local/bin",
	      "ei_ggc_user_groups": "video audio input users dialout"
    	}
    	
#### Attribute Description

The attributes in each of the above default configurations is outlined below:

		node_version: Version of NodeJS to be installed by the component
		vips_version: Version of the libvips library to be compiled/installed by the component
		device_name:  Template for the name of the device in EdgeImpulse... a unique suffix will be added to the name to prevent collisions when deploying to groups of devices
		launch: service launch type (typically just leave this as-is)
		sleep_time_sec: wait loop sleep time (component lifecycle stuff... leave as-is)
		lock_filename: name of lock file for this component (leave as-is)
		gst_args: optional GStreamer args, spaces replaced with ":", for custom video invocations
		eiparams: additional parameters for launching the Edge Impulse service (leave as-is)
		iotcore_backoff:  number of inferences to "skip" before publication to AWS IoTCore... this is used to control publication frequency (AWS $$...)
		iotcore_qos: MQTT QoS (leave as-is)
		ei_bindir: Typical location of where the Edge Impulse services are installed (leave as-is)
		ei_ggc_user_groups: A list of additional groups the GG service user will need to be members of to allow the Edge Impulse service to invoke and operate correctly (typically leave as-is)
		ei_sm_secret_id: ID of the Edge Impulse API Key within AWS Secret Manager
		ei_sm_secret_name: Name of the Edge Impulse API Key within AWS Secret Manager
		install_kvssink: Option (default: "no", on: "yes") to build and make ready the kvssink gstreamer plugin
		publish_inference_base64_image: Option (default: "no", on: "yes") to include a base64 encoded image that the inference result was based on
		enable_cache_to_file: Option (default: "no", on: "yes") to enable both inference and associated image to get written to a specified local directory as a pair: <guid>.img  and <guid>.json for each inference identified with a <guid>
		cache_file_directory: Option (default: "__none__") to specify the local directory when enable_cache_to_file is set to "yes"

### 6. Gather and install an EdgeImpulse API Key into AWS Secrets Manager

First we have to create an API Key in Edge Impulse via the Studio. 

Next, we will go into AWS Console -> Secrets Manager and press "Store a new secret". From there we will specify:

		1. Select "Other type of secret"
		2. Enter "ei_api_key" as the key NAME for the secret (goes in the "Key" section)
		3. Enter our actual API Key (goes in the "Value" section)
		4. Press "Next" 
		5. Enter "EI_API_KEY" for the "Secret Name" (actually, this is its Secret ID...)
		6. Press "Next"
		7. Press "Next"
		8. Press "Store"

### 7. Register the custom component via its recipe file

From the AWS Console -> IoTCore -> Greengrass -> Components, select "Create component". Then:

		1. Select the "yaml" option to Enter the recipe
		2. Clear the text box to remove the default "hello world" yaml recipe
		3. Copy/Paste the entire/edited contents of your EdgeImpulseLinuxServiceComponent.yaml file
		4. Press "Create Component"

If formatting and artifact access checks out OK, you should have a newly created component listed in your Custom Components AWS dashboard.  You will need to repeat these steps for the other 2 components:

		EdgeImpulseLinuxRunnerServiceComponent.yaml
		EdgeImpulseSerialRunnerServiceComponent.yaml

### 9. Modify the Greengrass TokenExchange Role with additional permissions

When you run a Greengrass component within Greengrass, a service user (typically a linux user called "ggc_user") invokes the component, as specified in the lifecycle section of your recipe. Credentials are passed to the invoked process via its environment (NOT by the login environment of the "ggc_user"...) during the invocation spawning process. These credentials are used by by the spawned process (typically via the AWS SDK which is part of the spawned process...) to connect back to AWS and "do stuff". These permissions are controlled by a AWS IAM Role called "GreengrassV2TokenExchangeRole".  We need to modify that role and add "Full AWS IoT Core Permission" as well as "AWS Secrets Manager Read/Write" permission.

To modify the role, from the AWS Console -> IAM -> Roles search for "GreengrassV2TokenExchangeRole", Then:

	1. Select "GreengrassV2TokenExchangeRole" in the search results list
	2. Select "Add Permissions" -> "Attach Policies"
	3. Search for "AWSIoTFullAccess", select it, then press "Add Permission" down at the bottom
	4. Repeat the search for "S3FullAccess" and "SecretsManagerReadWrite"

When done, your GreengrassV2TokenExchangeRole should now show that it has "AWSIoTFullAccess", "S3FullAccess" and "SecretsManagerReadWrite" permissions added to it. 

### 10. Deploy the custom component to a selected Greengrass edge device or group of edge devices. 

Almost done!  We can now go back to the AWS Console -> IoTCore -> Greengrass -> Deployments page and select a deployment (or create a new one!) to deploy our component down to as selected gateway or group of gateways as needed. 

When performing the deployment, its quite common to, when selecting one of our newly created custom components, to then "Customize" that component by selecting it for "Customization" and entering a new JSON structure (same structure as what's found in the component's assocated YAML file for the default configuration) that can be adjusted for a specific deployment (i.e. perhaps your want to change the DeviceName for this particular deployment or specify "gst_args" for a specific edge device(s) camera, etc...). This highlights the power and utility of the component and its deployment mechanism in AWS IoT Greengrass. 

After the deployment is initiated, on the FIRST invocation of a given deployment, expect to wait several moments (upwards of 5-10 min in fact) while the component installs all of the necessary pre-requisites that the component requires... this can take some time so be patient. You can also log into the edge gateway, receiving the component, and examine log files found in /greengrass/v2/logs. There you will see each components' current log file (same name as the component itself... ie. EdgeImpulseLinuxServiceComponent.log...) were you can watch the installation and invocation as it happens... any errors you might suspect will be shown in those log files. 


