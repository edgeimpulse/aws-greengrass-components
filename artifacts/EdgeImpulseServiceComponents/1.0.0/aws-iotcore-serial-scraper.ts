const { spawn } = require('child_process');
import { AWSIoTCoreConnector } from "./aws-iotcore-connector"
import { v4 as uuidv4 } from 'uuid';

// Payload typing
type ClassificationResult = { [k: string]: string | number };
type BoundingBox = {
    label: string;
    value: number;
    x: number;
    y: number;
    width: number;
    height: number;
};

type BasePayload = {
    time_ms: number;
    info?: string;
    id: string;
    ts: number;
    inference_count: number;
    total_inferences: number;
};

type DynamicPayload = {
    [key in AwsResultKey]?: AwsResult;
};

export type AwsResult = ClassificationResult | BoundingBox[];
export type AwsResultKey = 'c' | 'box' | 'grid';
export type Payload = BasePayload & DynamicPayload;

let totalInferenceCount = 0;

async function do_scrape_box(cmd: string, args: [], aws_iot : AWSIoTCoreConnector) {
    let t_str_inf = "";

    let dsp_time_ms = 0;
    let classification_time_ms = 0;
    let splits_uom = "";

    // run the command with the specified args and parse out the inferences... 
    console.log("Running: " + cmd + " with args: " + JSON.stringify(args));
    const run_cmd = spawn(cmd, args);
    run_cmd.stdout.on('data', async (data: string) => {
        if (data !== undefined) {
            try {
                //console.log("DEBUG: " + <string>data);
                const data_str = "" + data;
                const data_split = data_str.replace("(","").replace(")","").replace(":","").replace(".,","").split(" ");
                //console.log("DEBUG: " + JSON.stringify(data_split));
                if (data_split[0] === "Predictions") {
                    dsp_time_ms = Number(data_split[2]);
                    splits_uom = data_split[3];
                    classification_time_ms = Number(data_split[5]);
                } 
                if (data_str.includes("Taking photo")) {
                    if (t_str_inf.length > 0 && t_str_inf.includes("Edge Impulse") === false) {
                        const inf_split = t_str_inf.split(") ");
                        const total_time_ms = dsp_time_ms + classification_time_ms;
                        let time_details_json = {};
                        if (total_time_ms > 0) {
                            time_details_json = {"DSP": dsp_time_ms, "Classification": classification_time_ms, "UOM": splits_uom};
                        }
                        let inf_json = {"time":total_time_ms, "time_splits":{}, "box": [undefined], id: "", ts: 0, total_inferences: 0, inference_count: 0};
                        if (total_time_ms > 0) {
                            inf_json["time_splits"] = time_details_json;
                            dsp_time_ms = 0;
                            classification_time_ms = 0;
                            splits_uom = "";
                        }
                        const t_geom_str = "" + inf_split[1];
                        const t_inf_0 = "" + inf_split[0];
                        const inf_label_split = t_inf_0.replace("(","").split(" ");
                        const inf_box_0 = JSON.parse(t_geom_str.replace("[","{").replace("]","}").replace(/(['"])?([a-z0-9A-Z_]+)(['"])?:/g, '"$2": '));
                        inf_box_0["label"] = inf_label_split[0];
                        inf_box_0["value"] = Number(inf_label_split[1]);
                        inf_json["box"][0] = inf_box_0;
                        inf_json["id"] = uuidv4();
                        inf_json["ts"] = Date.now();
                        inf_json["inference_count"] = inf_box_0.length;
                        totalInferenceCount += inf_box_0.length; 
                        inf_json["total_inferences"] += totalInferenceCount;
                        
                        // send to AWS IoTCore
                        console.log("inference: " +  JSON.stringify(inf_json));
                        await aws_iot.sendInference(<Payload>(inf_json),"box");
                    }
                    t_str_inf = "";
                }
                const split_data = data_str.split(/\r?\n|\r/);
                if (split_data[3] !== undefined && split_data.length > 3) {
                    const t_str_1 = "" + split_data[1];
                    if (t_str_1.includes("#Object detection results")) {
                        const t_str_3 = "" + split_data[3];
                        if (t_str_3.includes("No objects found")) {
                            // skip
                            ;
                        }
                        else {
                            t_str_inf = t_str_inf + t_str_3.trim();
                        }
                    }
                }
                else if (split_data.length > 0) {
                    const t_str_0 = "" + split_data[0];
                    if (t_str_0.includes("Taking photo")) {
                        // skip
                        ;
                    }
                    else {
                        t_str_inf = t_str_inf + t_str_0.trim();
                    }
                }
            }
            catch(err) {
                // caught exception during parse... ignore
                console.log("IE: Exception during serial parse: " + err + ". Ignoring...");
            }
        }
    });
}

// main() function
async function main() {
    console.log("Connecting to AWS IoTCore...");
    const aws_iot = await new AWSIoTCoreConnector({});
    await aws_iot.connect();
    console.log("Begin parsing output...");
    do_scrape_box(<string>process.env.EI_SERIAL_RUNNER_CMD, [],aws_iot);
}

// call main()
console.log("Calling main()...");
main();
console.log("Exiting...");