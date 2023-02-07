# Bonding ZeroTier network interfaces

Network IO in zerotier-one is infamously single threaded. This means you can push packets around only as fast as 1 core can go. ZeroTier will be multithreaded someday. 

While we wait for multithreaded zerotier, we can create multiple zerotier-one processes and [bond](https://wiki.linuxfoundation.org/networking/bonding) them together with the Linux kernel, and they'll load balance.  

This doesn't magically double bandwidth for each core added, but it does help.

We think this would be most applicable to big router or proxy nodes that service many clients. 

We weren't able to get much improvement in max bandwidth by creating bonds on 2 machines and pointing them at each other. 

## Summary
- Start multiple zerotier-one processes
- Configure `devicemap` so they don't all use the same interface name
- Join each process to the same network
- Enable "bridging" in Central
- Put the zerotier interfaces into a Linux interface bond.

## Install system zerotier
use as a backdoor, adds zerotier-cli in your path

`curl -s https://install.zerotier.com | bash`


## Set some convenience vars

``` shell
mkdir zerotiers; cd zerotiers;
export BASE_DIR=$(pwd)
export NETWORKID=<your network id>
export IP=10.1.1.1/24
export MAC=02:22:22:22:22:24
```


## Setup and Start Multiple ZeroTiers

``` shell

for i in `seq ${NUM_ZT}`; do
    mkdir -p $BASE_DIR/node${i};
    echo "$NETWORKID=zt-node${i}" > ${BASE_DIR}/node${i}/devicemap
done

for i in `seq ${NUM_ZT}`; do
    zerotier-one -U -d -p199${i}3 ${BASE_DIR}/node${i}/;
done

```

## Join each process to the same network

``` shell
for i in `seq ${NUM_ZT}`; do
    zerotier-cli -D${BASE_DIR}/node${i} info
    zerotier-cli -D${BASE_DIR}/node${i} join $NETWORKID
    zerotier-cli -D${BASE_DIR}/node${i} set $NETWORKID allowManaged=0 > /dev/null
    alias z${i}="zerotier-cli -D${BASE_DIR}/node${i}"
done
```

We set up an alias for zeroiter-cli above. You can do `z1 <command>` to do `zerotier-cli <command>` for that node. `z1 info`

## Enable Bridging for each of these newly created node
ZeroTier doesn't like receiving packets for other MAC addresses by default. This is a [security feature](https://docs.zerotier.com/zerotier/manual#224ethernetbridginganame2_2_4a)

- go to my.zerotier.com/network/$NETWORKID
- click the wrench icon
- enable bridging
- actually, lets do it with the api

Put a my.zerotier.com API token in a file named "token"

``` shell
for i in `seq ${NUM_ZT}`; do
    ID=$(zerotier-cli -D${BASE_DIR}/node${i} info | cut -d" " -f 3)
    curl -s -X POST -H "Authorization: token $(cat token)" https://api.zerotier.com/api/v1/network/$NETWORKID/member/$ID -d \
    "{ \"name\": \"bond-node-${i}\", \"config\": { \"activeBridge\": true }}" > /dev/null && echo "ok $ID"
done
```

## bond them in linux
### create the bond interface

``` shell
ip link add zt-bond type bond miimon 100 mode balance-alb xmit_hash_policy 1
```

Other bond types include balance-rr and balance-xor

### configure the bond
ZeroTier isn't managing the IP address of the bonded node. 
Pick an available IP address in your network's subnet. 

I'm not sure if manually assiging a MAC is needed. The bond will get the MAC of the first interface that joins the bond.

If you want to edit the bond, you need to bring everything down and back up like so:
``` shell
for i in `seq ${NUM_ZT}`; do
    ip link set zt-node${i} down
    ip link set nomaster zt-node${i}
done

ip link set zt-bond down
ip link set zt-bond type bond miimon 100 mode balance-alb xmit_hash_policy 1

for i in `seq ${NUM_ZT}`; do
    ip link set zt-node${i} master zt-bond
done

# ip link set zt-bond address $MAC
ip addr add $IP dev zt-bond
ip link set zt-bond up

for i in `seq ${NUM_ZT}`; do
    ip link set zt-node${i} up
done
```

## Pin zerotier processes to a specific CPU core
If you want to try it, it might improve performance a little


``` shell

for i in `seq ${NUM_ZT}`; do
    core=$(expr $i - 1)
    taskset -c ${core} "zerotier-one -U -d -p199${i}3 ${BASE_DIR}/node${i}/;"
done
```

## Kill these processes

`killall zerotier-one`

or 

``` shell
for i in `seq ${NUM_ZT}`; do
    kill `cat ${BASE_DIR}/node${i}/zerotier-one.pid`
done
```

## Production
Configuring interface bonds and zerotier like this in a reproducible, production way is left as an exercise to the reader. Maybe we'll wrap it up in a script later. 



