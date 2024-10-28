#!/bin/bash

LOG_FILE=$1

# Install...
if [ ! -d ./node_modules ]; then
   echo "Installing..."
   npm install .
fi

# DEBUG
# printenv >> ${LOG_FILE}
# id >> ${LOG_FILE}

# Launch
echo "Starting Serial Service..." >> ${LOG_FILE}

while true
do
    ts-node ./aws-iotcore-serial-scraper.ts 2>&1 1>> ${LOG_FILE}
    echo "Relaunching serial service..." >> ${LOG_FILE}
    sleep 5
done