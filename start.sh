#! /bin/bash

# Reset iC880a PIN
SX1301_RESET_BCM_PIN=25
echo "$SX1301_RESET_BCM_PIN"  > /sys/class/gpio/export 
echo "out" > /sys/class/gpio/gpio$SX1301_RESET_BCM_PIN/direction 
echo "0"   > /sys/class/gpio/gpio$SX1301_RESET_BCM_PIN/value 
sleep 0.1  
echo "1"   > /sys/class/gpio/gpio$SX1301_RESET_BCM_PIN/value 
sleep 0.1  
echo "0"   > /sys/class/gpio/gpio$SX1301_RESET_BCM_PIN/value
sleep 0.1
echo "$SX1301_RESET_BCM_PIN"  > /sys/class/gpio/unexport

# Test the connection, wait if needed.
while [[ $(ping -c1 google.com 2>&1 | grep " 0% packet loss") == "" ]]; do
  echo "[TTN Gateway]: Waiting for internet connection..."
  sleep 30
  done

INSTALL_DIR="/opt/ttn-gateway"
LOCAL_CONFIG_FILE=$INSTALL_DIR/bin/local_conf.json
GLOBAL_CONFIG_FILE=$INSTALL_DIR/bin/global_conf.json

if [ ! -e $GLOBAL_CONFIG_FILE ]; then
  echo "ERROR: No global_conf.json found."
  exit 1
fi

if [ ! -e $LOCAL_CONFIG_FILE ]; then
  echo "ERROR: No local_conf.json found."
  exit 1
fi

GATEWAY_EUI_NIC="eth0"

if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
  GATEWAY_EUI_NIC="wlan0"
fi

if [[ `grep "$GATEWAY_EUI_NIC" /proc/net/dev` == "" ]]; then
  echo "ERROR: No network interface found. Cannot set gateway ID."
  exit 1
fi

GATEWAY_EUI=$(ip link show $GATEWAY_EUI_NIC | awk '/ether/ {print $2}' | awk -F\: '{print $1$2$3"FFFE"$4$5$6}')
GATEWAY_EUI=${GATEWAY_EUI^^} # toupper

echo "[TTN Gateway]: Use Gateway EUI $GATEWAY_EUI based on $GATEWAY_EUI_NIC"

# If there's a remote config, try to update it
if [ -d ../gateway-remote-config ]; then
    # First pull from the repo
    pushd ../gateway-remote-config/
    git pull
    git reset --hard
    popd

    # And then try to refresh the gateway EUI and re-link local_conf.json
    if [ -e $LOCAL_CONFIG_FILE ]; then rm $LOCAL_CONFIG_FILE; fi;
    ln -s $INSTALL_DIR/gateway-remote-config/$GATEWAY_EUI.json $LOCAL_CONFIG_FILE

else
    # Retrieve gateway ID in local_conf.json
    GATEWAY_EUI_JSON=$(cat $LOCAL_CONFIG_FILE | grep "\"gateway_ID\":" | cut -d '"' -f4)
    
    if [[ $GATEWAY_EUI_JSON == "" ]]; then
         echo "ERROR: Cannot parse Gateway ID in local_conf.json, make sure it is not empty"
         exit 1
    fi
    
    echo "Gateway ID found from local_conf.json: $GATEWAY_EUI_JSON"
    
    # Check if the gateway ID is equal to GATEWAY_EUI
    if [[ $GATEWAY_EUI_JSON != $GATEWAY_EUI ]]; then
        echo "Gateway ID not equal, replacing Gateway ID in local_conf.json with actual Gateway EUI"
        sed -i "s/$GATEWAY_EUI_JSON/$GATEWAY_EUI/" $LOCAL_CONFIG_FILE
    fi
fi

# Fire up the forwarder.  
./connect.sh & ./poly_pkt_fwd
