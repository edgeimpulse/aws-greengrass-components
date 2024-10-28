import { IoTDataPlaneClient, PublishCommand } from "@aws-sdk/client-iot-data-plane";

const PREFIX = '\x1b[34m[AWS_IOTCORE]\x1b[0m';

export class AWSIoTCoreConnector {

    private _debug : boolean;
    private _not_silent : boolean;
    private _inference_output_topic : string;
    private _metrics_output_topic : string;
    private _command_input_topic : string;
    private _command_output_topic : string;
    private _iot: IoTDataPlaneClient | undefined;
    private _client_config;
    private _iotcore_qos: number; 
    private _connected: boolean;
    private _delay_countdown: number; 
    private _delay_inferences: number;

    constructor(opts: any) {
        this._debug = false;
        this._not_silent = (!opts.silentArgv);
        this._inference_output_topic = "";
        this._metrics_output_topic = "";
        this._command_input_topic = "";
        this._command_output_topic = "";
        
        this._client_config = { region: process.env.AWS_REGION };
        this._iot = undefined;
        this._connected = false;
        this._delay_countdown = 0;
        this._iotcore_qos = Number((<string>process.env.EI_IOTCORE_QOS));

        // We can slow down the publication to IoTCore to save IoTCore message cost$.  
        // set "iotcore_backoff" in Greengrass component config to "n" > 0 to enable countdown backoff... "-1" to disable... (default: "10")
        this._delay_inferences = Number((<string>process.env.EI_OUTPUT_BACKOFF_COUNT));
    }

    createTopics() {
        // Inference result topic
        this._inference_output_topic = (<string>process.env.EI_INFERENCE_OUTPUT_TOPIC);

        // Model metrics status topic
        this._metrics_output_topic = (<string>process.env.EI_METRICS_OUTPUT_TOPIC);

        // XXX Future topics for command/control
        this._command_input_topic = (<string>process.env.EI_COMMAND_INPUT_TOPIC);
        this._command_output_topic = (<string>process.env.EI_COMMAND_OUTPUT_TOPIC);

        // Report Topic Config
        if (this._not_silent) {
            console.log(PREFIX + " EI AWS IoTCore Topics - Model Inferences: " + this._inference_output_topic + 
                                                        " Model Metrics: " + this._metrics_output_topic +
                                                        " (Future) Command Input: " + this._command_input_topic + 
                                                        " (Future) Command Output: " + this._command_output_topic);
        }
    }

    async connect() {
        if (this._iot === undefined) {
            if (this._not_silent) {
                // not connected.. so connect to IoTCore
                console.log(PREFIX + " EI: Connecting to IoTCore...");
            }

            try {
                // build topics
                this.createTopics();

                // allocate... 
                this._iot = new IoTDataPlaneClient(this._client_config);

                // we are connected!
                this._connected = true;
            }
            catch(err) {
                // unable to allocate
                if (this._not_silent) {
                    // not connected.. so connect to IoTCore
                    console.log(PREFIX + " EI: ERROR - Unable to allocate IoTDataPlaneClient with exception: " + err);
                }
                this._iot = undefined;
                this._connected = false;
            }
        }
        else {
            // already connected... OK
            if (this._debug) {
                console.log(PREFIX + " EI: Already connected to IoTCore. OK.");
            }
            this._connected = true;
        }
        return this.is_connected();
    }

    is_connected() {
        return this._connected;
    }

    is_empty_inference(payload: object, key: string) {
        let is_empty = true;
        if (payload !== undefined) {
            const payload_str = JSON.stringify(payload);
            if (payload_str !== undefined && payload_str !== "[]") {
                const key_str = JSON.stringify((<any>payload)[key]);
                if (key_str !== undefined && key_str !== "[]") {
                    is_empty = false;
                }
            }
        }
        return is_empty;
    }

    async send_model_metrics(payload: object) {
        if (this._iot !== undefined && this.is_connected() === true && this._metrics_output_topic !== undefined && this._metrics_output_topic.length > 0) {
            // Create the PublishCommand with the PublishRequest
            const input = { 
                topic: this._metrics_output_topic,
                qos: this._iotcore_qos,
                payload: Buffer.from(JSON.stringify(payload))
            };
            const command = new PublishCommand(input);

            // publish!
            try {
                // send the publication and await the response
                const response = await this._iot.send(command);
                
                // response
                if (this._debug) {
                    console.log(PREFIX + " EI: Model Metrics Publication Response: " + JSON.stringify(response));
                }
            }
            catch(err) {
                if (this._not_silent) {
                    // exception during send()...
                    console.log(PREFIX + " EI: ERROR - IoTDataPlaneClient.send() errored with exception: " + err);
                }
            }
        }
        else if (this._iot !== undefined && this.is_connected() === true) {
            // no model metrics topic
            if (this._not_silent) {
                console.log(PREFIX + " EI: ERROR - No model metrics topic specified in configuration... not sending inference.");
            }
        }
        else {
            // not connected
            if (this._not_silent) {
                console.log(PREFIX + " EI: ERROR - Not connected to IoTCore... not sending mdoel metrics.");
            }
        }
    }

    async send_inference(payload: object, key: string) {
        if (this._iot !== undefined && this.is_connected() === true && this._inference_output_topic !== undefined && this._inference_output_topic.length > 0) {
            if (this.is_empty_inference(payload,key)) {
                // empty inference ... so save money and don't publish
                if (this._debug) {
                    console.log(PREFIX + " EI: Inference is empty... not sending empty inference (OK).");
                }
            }
            else {
                if (this._delay_inferences > 0) {
                    ++this._delay_countdown;
                    if (this._delay_countdown >= this._delay_inferences) {
                        // reset:
                        this._delay_countdown = 0;

                        // FIRE: publish inference as JSON to IoTCore...
                        if (this._debug) {
                            console.log(PREFIX + " EI: Publishing inference result: " + JSON.stringify(payload) +  " to topic: " + this._inference_output_topic);
                        }

                        // Create the PublishCommand with the PublishRequest
                        const input = { 
                            topic: this._inference_output_topic,
                            qos: this._iotcore_qos,
                            payload: Buffer.from(JSON.stringify(payload))
                        };
                        const command = new PublishCommand(input);

                        // publish!
                        try {
                            // send the publication and await the response
                            const response = await this._iot.send(command);
                            
                            // response
                            if (this._debug) {
                                console.log(PREFIX + " EI: Publication Response: " + JSON.stringify(response));
                            }
                        }
                        catch(err) {
                            if (this._not_silent) {
                                // exception during send()...
                                console.log(PREFIX + " EI: ERROR - IoTDataPlaneClient.send() errored with exception: " + err);
                            }
                        }
                    }
                }
                else {
                    // Full Speed: publish inference as JSON to IoTCore...
                    if (this._debug) {
                        console.log(PREFIX + " EI: Publishing inference result: " + JSON.stringify(payload) +  " to topic: " + this._inference_output_topic);
                    }

                    // Create the PublishCommand with the PublishRequest
                    const input = { 
                        topic: this._inference_output_topic,
                        payload: Buffer.from(JSON.stringify(payload))
                    };
                    const command = new PublishCommand(input);

                    // publish!
                    try {
                        // send the publication and await the response
                        const response = await this._iot.send(command);
                        
                        // response
                        if (this._debug) {
                            console.log(PREFIX + " EI: Publication Response: " + JSON.stringify(response));
                        }
                    }
                    catch(err) {
                        if (this._not_silent) {
                            // exception during send()...
                            console.log(PREFIX + " EI: ERROR - IoTDataPlaneClient.send() errored with exception: " + err);
                        }
                    }
                }
            }
        }
        else if (this._iot !== undefined && this.is_connected() === true) {
            // no publication topic
            if (this._not_silent) {
                console.log(PREFIX + " EI: ERROR - No model inference publication topic specified in configuration... not sending inference results.");
            }
        }
        else {
            // not connected
            if (this._not_silent) {
                console.log(PREFIX + " EI: ERROR - Not connected to IoTCore... not sending inference.");
            }
        }
    }
}