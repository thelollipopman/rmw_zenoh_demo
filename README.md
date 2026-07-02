# Understanding Zenoh and rmw_zenoh
This section is mainly for constructing a mental model for understanding Zenoh and how rmw_zenoh implements it. Skip to the [demo](#demo) if needed. The content is based off the official docs for [Zenoh](https://zenoh.io/docs) and [rmw_zenoh](https://github.com/ros2/rmw_zenoh) (as well as conversations with an LLM :p). Note that `rmw_zenoh` implements Zenoh in a specific way with different default behaviours, so the terms `Zenoh` and `rmw_zenoh` will be used to distinguish wherever they differ. 

## Zenoh
All Zenoh applications run as nodes, where their behaviours are configured in a json5 config file. Different communication models / topologies use different nodes. See their [docs](https://zenoh.io/docs/getting-started/deployment) for more info. All the available parameters for the config file can be found carefully documented in the [Zenoh default config file](https://github.com/eclipse-zenoh/zenoh/blob/main/DEFAULT_CONFIG.json5) and [rmw_zenoh config files](https://github.com/ros2/rmw_zenoh/tree/rolling/rmw_zenoh_cpp/config) comments, but the important ones will also be documented below.

There are 2 ways to spawn a `Zenoh` node, both of which allow you to pass a config file:
- `zenohd` executable. By default it spawns a router.
- `Zenoh` library. By default it should use the [default config file](https://github.com/eclipse-zenoh/zenoh/blob/main/DEFAULT_CONFIG.json5) params. 

## rmw_zenoh
`rmw_zenoh`, however, distinguishes between 2 types of config files:
- router config file: used when spawning a `zenohd` router. 
- session config file: used when running a ROS context.


### mode
Each node can run in one of 3 modes:
- `"peer"`: default mode, can open sessions with multiple nodes (usually peers or routers), enabling peer to peer communication.
- `"router"`: can open sessions with multiple nodes (clients, peers or routers) and route application communication between them
- `"client"`: can only open a single session at any one time (usually a router)
```
{
  mode: "peer"
}
```

There are multiple ways for 2 nodes to communicate:
- Directly connect on startup: One node initiates the connection through [connect](#connect) parameter, and the other listens through the [listen](#listen) parameter.
- Through router(s): A router node (or a chain of router nodes) must connect to both nodes.
- Discovery through scouting (multicast/gossip): See [scouting](#scouting). Client nodes cannot participate in gossip scouting.

### connect
On startup, the node attempts to connect to other nodes' endpoints, listed in `connect/endpoints` in the format `<protocol>/<ip address>:<port>`. Here, assigning static ip addresses is recommended, and port 7447 is the `rmw_zenoh` default. For the `rmw_zenoh` default config, peer and router nodes do not timeout, but client nodes have 0 retries and exit after failing to connect (see `connect/timeout_ms`, `connect/exit_after_failure` and `connect/retry` for more info). Hence, client nodes should only be started after their corresponding router (or peer) nodes. 
```
connect: {
  endpoints: [
    "tcp/localhost:7447"
  ],
}
```
`rmw_zenoh` default: `zenohd` router doesn't connect to any endpoint on startup, while peers connect to `localhost:7447`.


### listen
Similarly, on startup, the node listens to others' connection attempts on its own endpoints, listed in `listen/endpoints` in the format `<protocol>/<ip address>:<port>`. Again, port 7447 is the `rmw_zenoh` default. Use the wildcard address `tcp/[::]:7447` to listen on all interface addresses, i.e. loopback (localhost or 127.0.0.1), wlan0 (e.g. 192.168.1.23) and eth0 (e.g. 10.42.0.1). Use `tcp/<my_address>:0` to listen on all ports.
```
listen: {
  endpoints: [
    "tcp/localhost:7447"
  ],
}
```
`rmw_zenoh` default: `zenohd` router listens on `localhost:7447`, while peers listen on `localhost:0` (all ports).

### scouting
Instead of explicitly setting endpoints for direct connections through the `connect` and `listen` parameters, nodes can discover one another via multicast or gossip (or both), and then autoconnect. If nodes communicated through an intermediate router node prior to discovery via scouting, they can open up direct peer to peer sessions to one another which persist even after the router is down. 

To use multicast, set `scouting/multicast/enabled` to true so that the node joins the multicast group and discovers other nodes in the group. If `scouting/multicast/listen` is false, it is not discoverable by scout messages from other multicast nodes. `scouting/multicast/autoconnect` dictates what kind of multicast nodes it connects to. `scouting/multicast/autoconnect_strategy` controls strategy for autoconnection. If set to "always", it always attempts to autoconnect which may result in redundant connections. If set to "greater-zid", it will connect to a node with a lesser Zenoh id (see `id` for more info).

```
scouting: {
  multicast: {
    enabled: false,
    autoconnect: { router: [], peer: ["router", "peer"], client: ["router"] },
    autoconnect_strategy: { peer: { to_router: "always", to_peer: "greater-zid" } },
    listen: true,
  }
}
```
`rmw_zenoh` default: multicast is not enabled, and if enabled, routers do not autoconnect to any node.

To use gossip, set `scouting/gossip/enabled` to true. Then the node can:
- send gossip messages about any connected node to any other connected node. These 2 nodes may then discover and autoconnect to each other, provided their target/autoconnect
settings allow it and the advertised endpoints are reachable. `scouting/gossip/target` controls which nodes to send the gossip messages to. If `scouting/gossip/multihop` is true, the node will relay gossip messages it receives. Otherwise it only relays its own gossip messages about its directly connected nodes. 
- discover and autoconnect via gossip messages received from other nodes. 

```
scouting: {
  gossip: {
    enabled: true,
    multihop: false,
    target: { router: ["router", "peer"], peer: ["router"]},
    autoconnect: { router: [], peer: ["router", "peer"] },
    autoconnect_strategy: { peer: { to_router: "always", to_peer: "greater-zid" } },
  }
}
```




# Setup
Ensure [Docker](https://docs.docker.com/engine/install/) is installed 

Pull any of the [official ROS2 images](https://hub.docker.com/r/osrf/ros) and run a container interactively in host mode. This demo uses `ros:kilted-ros-core` and names the container "demo":
```
docker create -it --name demo --network host ros:kilted-ros-core
docker start -ai demo
```

In the Docker container, follow the instructions to install [rmw_zenoh](https://github.com/ros2/rmw_zenoh#installation). This demo installed the binaries instead of building from source:
```
sudo apt update && sudo apt install ros-kilted-rmw-zenoh-cpp
```

# Demo
The demo runs the demo talker and listener nodes from [demo_nodes_cpp](https://index.ros.org/p/demo_nodes_cpp/) using [rmw_zenoh](https://github.com/ros2/rmw_zenoh) as middleware. It uses 2 Raspberry Pi's on the same network, running ROS2 Kilted with Docker, but should also work for any 2 hosts on the same network.

### Setup
When opening any new terminal, do the following:

- Source ROS. Source your base ROS (replace \<DISTRO\> with your ROS distro) if you installed the `rmw_zenoh` binaries, but if you built rmw_zenoh from source in your workspace, then source the `setup.bash` from the workspace instead.
```
source opt/ros/<DISTRO>/setup.bash

# If built from source
# cd ~/my_workspace
# source install/setup.bash
```
- Terminate the ROS2 daemon started with another RMW (ROS Middleware). If you are already running an rmw_zenoh process then skip this. Without this step, ROS 2 CLI commands (e.g. ros2 node list) may not work properly since they would query ROS graph information from the ROS 2 daemon that may have been started with different a RMW.
```
pkill -9 -f ros && ros2 daemon stop
```

- Configure ROS to use rmw_zenoh for middleware instead of the default Fast DDS:
```
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
```

To use different configs than the `rmw_zenoh` default [router config](https://github.com/ros2/rmw_zenoh/blob/rolling/rmw_zenoh_cpp/config/DEFAULT_RMW_ZENOH_ROUTER_CONFIG.json5) / [session config](https://github.com/ros2/rmw_zenoh/blob/rolling/rmw_zenoh_cpp/config/DEFAULT_RMW_ZENOH_SESSION_CONFIG.json5), make a copy of the default config file and change the desired parameters. Then set the `ZENOH_ROUTER_CONFIG_URI` / `ZENOH_SESSION_CONFIG_URI` environment variable to the path to your modified config file. The default config files without the verbose comments can also be found [in this repo](./default_rmw_zenoh_configs/)
```
export ZENOH_ROUTER_CONFIG_URI=path/to/my/router_config.json5
export ZENOH_SESSION_CONFIG_URI=path/to/my/session_config.json5
```
If a config file is written from scratch with just the desired modified parameters, unspecified parameters may fall back to `Zenoh` instead of `rmw_zenoh` default values, hence the rationale for modifying from the `rmw_zenoh` default config files.

For the following demos, you can create a copy of the default config files and change only the parameters described, or download the [modified config files](./demo_configs/) directly. Be sure to change the IP addresses to your hosts' actual addresses.


### 1. Routers and peers
This is the standard configuration for `rmw_zenoh`, as prescribed by the default config files:
- Every host/machine spawns a `zenohd` router that connects to other routers on startup, relaying gossip [scouting](#scouting) messages to othe routers and peers.
- Within each host/machine, every ROS context spawns a Zenoh peer that connects to its host's router on startup. Each peer discovers other peers on the same host through the router's gossip, opening up direct sessions for peer-to-peer communication. 
- All inter-host communication (e.g. a ROS node on host 1 to a ROS node on host 2) is relayed through the routers. 

```mermaid
flowchart TD
  subgraph h2 [Host 2]
    direction TD
    idr2(router 2)
    idp3(peer 3) 
    idp4(peer 4)
    idr2<-->idp3
    idr2<-.->idp3 
    idr2<-->idp4
    idr2<-.->idp4
    idp3<--after discovery through router 2-->idp4
  end
  subgraph h1 [Host 1]
    direction TD
    idr1(router 1)
    idp1(peer 1) 
    idp2(peer 2)
    idr1<-->idp1
    idr1<-.->idp1 
    idr1<-->idp2
    idr1<-.->idp2
    idp1<--after discovery through router 1-->idp2
  end
  idr2<-->idr1
  LH1(( ))
  RH1(( transport ))
  LH2(( ))
  RH2(( discovery ))
  subgraph legend [Legend]
    direction LR
    LH1<-->RH1
    LH2<-.->RH2
    RH1~~~LH2
  end

  legend~~~h1
  legend~~~h2

  classDef hidden fill:#00000000,stroke:#00000000,width:0px,height:0px;
  classDef router fill:#b8a6d9,stroke:#333,stroke-width:1px,color:#000;
  classDef peer fill:#d9a6bf,stroke:#333,stroke-width:1px,color:#000;
  classDef legend fill:#fff,stroke:#999,stroke-width:1px,color:#000;
  classDef invisible fill:none, stroke:none, color:transparent;
    class LH1,RH1,LH2,RH2 hidden;
    class idr1,idr2 router;
    class idp1,idp2,idp3,idp4 peer;
```

We test a simplified version of this configuration with the `demo_nodes_cpp` talker and listener as such:

```mermaid
flowchart TD
  subgraph h2 [Host 2]
    direction TD
    idr2(router 2)
    idp3(listener) 
    idr2<-->idp3
    idr2<-.->idp3
  end
  subgraph h1 [Host 1]
    direction TD
    idr1(router 1)
    idp1(talker) 
    idp2(listener)
    idr1<-->idp1
    idr1<-.->idp1 
    idr1<-->idp2
    idr1<-.->idp2
    idp1<--after discovery through router 1-->idp2
  end
  idr2<-->idr1
  LH1(( ))
  RH1(( transport ))
  LH2(( ))
  RH2(( discovery ))
  subgraph legend [Legend]
    direction LR
    LH1<-->RH1
    LH2<-.->RH2
    RH1~~~LH2
  end

  legend~~~h1
  legend~~~h2

  classDef hidden fill:#00000000,stroke:#00000000,width:0px,height:0px;
  classDef router fill:#b8a6d9,stroke:#333,stroke-width:1px,color:#000;
  classDef peer fill:#d9a6bf,stroke:#333,stroke-width:1px,color:#000;
  classDef legend fill:#fff,stroke:#999,stroke-width:1px,color:#000;
  classDef invisible fill:none, stroke:none, color:transparent;
    class LH1,RH1,LH2,RH2 hidden;
    class idr1,idr2 router;
    class idp1,idp2,idp3 peer;
```

The only required change is to make `host 1` and `host 2` connect to each other's address on port 7447 startup. Technically this is redundant since only either `host 1` or `host 2` needs to initiate the connection while the other just listens. By default their `listen/endpoints` parameter is listening on all interface addresses on port 7447 already, so no changes are needed.

Host 1 router config:
```
{
  mode: "router",
  connect: {
    endpoints: ["tcp/<Host 2 IP>:7447"]
  },
  listen: {
    endpoints: [
      "tcp/[::]:7447"
    ],
  },
  scouting: {
    gossip: {
      enabled: true,
      target: { router: ["router", "peer"], peer: ["router"]},
    },
  },
}
```

Host 2 router config:
```
{
  mode: "router"
  connect: {
      endpoints: ["tcp/<Host 1 IP>:7447"]
  },
  listen: {
    endpoints: [
      "tcp/[::]:7447"
    ],
  },
  scouting: {
    gossip: {
      enabled: true,
      target: { router: ["router", "peer"], peer: ["router"]},
    },
  },
}
```

Instead of hardcoding `connect/endpoints`, you could also make routers discover one another via multicast. However, every router would be connected to every other reachable router, which may be undesirable:
```
{
  multicast: {
    enabled: true,
    autoconnect: {router: ["router"]}
  }
}
```

By default the peers are configured to connect to the router on port 7447 on startup, then receive gossip messages from it before autoconnecting to other peers, so no changes required:
```
{
  mode: "peer",
  connect: {
    endpoints: [
      "tcp/localhost:7447"
    ],
  },
  listen: {
    endpoints: [
      "tcp/localhost:0"
    ],
  },
  scouting: {
    gossip: {
      enabled: true,
      autoconnect: { router: [], peer: ["router", "peer"] },
    },
  },
}
```

Start the routers on both hosts:
```
ros2 run rmw_zenoh_cpp rmw_zenohd
```

Start the talker on Host 1:
```
ros2 run demo_nodes_cpp talker
```

Start the listeners on both hosts:
```
ros2 run demo_nodes_cpp listener
```

Check that the published messages are in sync on the talker and listeners. You can also verify on host 2 that there are 2 subscribers to the `/chatter` topic:
```
ros2 topic info /chatter
```


### 2. Single router and client
As per the [docs](https://github.com/ros2/rmw_zenoh#connecting-to-the-zenoh-router-on-another-host), in some scenarios we want to connect to the Zenoh router on another host directly for better performance. For example, it's more efficient to connect to the Zenohd of a robot while running RViz remotely. 

```mermaid
flowchart TD
  subgraph h2 [Host 2]
    direction TD
    idc1(client 1)
  end
  subgraph h1 [Host 1]
    direction TD
    idr1(router 1)
    idp1(peer 1) 
    idp2(peer 2)
    idr1<-->idp1
    idr1<-.->idp1 
    idr1<-->idp2
    idr1<-.->idp2
    idp1<--after discovery through router 1-->idp2
  end
  idc1<-->idr1
  LH1(( ))
  RH1(( transport ))
  LH2(( ))
  RH2(( discovery ))
  subgraph legend [Legend]
    direction LR
    LH1<-->RH1
    LH2<-.->RH2
    RH1~~~LH2
  end

  legend~~~h1
  legend~~~h2

  classDef hidden fill:#00000000,stroke:#00000000,width:0px,height:0px;
  classDef router fill:#b8a6d9,stroke:#333,stroke-width:1px,color:#000;
  classDef peer fill:#d9a6bf,stroke:#333,stroke-width:1px,color:#000;
  classDef client fill:#328da8,stroke:#333,stroke-width:1px,color:#000;
  classDef legend fill:#fff,stroke:#999,stroke-width:1px,color:#000;
  classDef invisible fill:none, stroke:none, color:transparent;
    class LH1,RH1,LH2,RH2 hidden;
    class idr1 router;
    class idp1,idp2 peer;
    class idc1 client;
```
For the demo we will run a simple remote listener client on Host 2 which connects to Host 1's router on startup, with the following session config:
```
{
  mode: "client",
  connect: {
    endpoints: ["tcp/<Host 1 IP>:7447"]
  }
}
```

Here we can technically also use "peer" mode, so Host 2's node will connect directly to Host 1's peers after discovery via the router. But this may be undesirable if they are not reachable and it's cleaner to expose a single endpoint through the router. 

The router and session configs for Host 1 are the same as in the previous example.    

Start the router on just Host 1:
```
ros2 run rmw_zenoh_cpp rmw_zenohd
```

Start the talker on Host 1:
```
ros2 run demo_nodes_cpp talker
```

Start the listeners on both hosts:
```
ros2 run demo_nodes_cpp listener
```

Check that the published messages are in sync on the talker and listeners.

### 3. No routers and only multicast scouting
This fully peer to peer configuration may be desirable for lower latency for small enough systems on the same network. This is similar to Fast DDS' multicast configuration.

```mermaid
flowchart TD
  subgraph h2 [Host 2]
    direction TD
    idp3(peer 3) 
    idp4(peer 4)
    idp3<-->idp4
  end
  subgraph h1 [Host 1]
    direction TD
    idp1(peer 1) 
    idp2(peer 2)
    idp1<-->idp2
  end
  idp1<-->idp3
  idp4<-->idp2
  idp2<-->idp3
  idp4<-->idp1
  
  LH1(( ))
  RH1(( transport ))
  LH2(( ))
  RH2(( discovery ))
  subgraph legend [Legend]
    direction LR
    LH1<-->RH1
    LH2<-.->RH2
    RH1~~~LH2
  end

  legend~~~h1
  legend~~~h2

  classDef hidden fill:#00000000,stroke:#00000000,width:0px,height:0px;
  classDef peer fill:#d9a6bf,stroke:#333,stroke-width:1px,color:#000;
  classDef legend fill:#fff,stroke:#999,stroke-width:1px,color:#000;
  classDef invisible fill:none, stroke:none, color:transparent;
    class LH1,RH1,LH2,RH2 hidden;
    class idp1,idp2,idp3,idp4 peer;
```

We shall only run a single talker on Host 1 (and not on Host 2 to avoid duplicate /chatter messaages) and a single listener on Host 2.

The peers do not need to connect to explicit endpoints on startup since we are using multicast for discovery. By default they listen only on localhost, so we make them listen to all interface addresses so peers on different hosts are reachable. Then we enable multicast to true, and by default peers already autoconnect to other peers. Session config for both hosts:
```
mode: "peer",
  connect: {
    endpoints: []
  },
  listen: {
    endpoints: ["tcp/[::]:7447"]
  },
  scouting: {
  multicast: {
    enabled: true,
    autoconnect: { router: [], peer: ["router", "peer"], client: ["router"] },
  },
}
```

Start the talker on Host 1:
```
ros2 run demo_nodes_cpp talker
```

Start the listener on Host 2:
```
ros2 run demo_nodes_cpp listener
```

Check that the published messages are in sync on the talker and listener without the need for a router.

# Usage with IBSS
To use `rmw_zenoh` over IBSS, simply ensure that the `connect\endpoints` and `listen\endpoints` parameters in the zenoh router and session config files are set to the correct IBSS IP addresses.

### Setting up IBSS

Thx to James for this part lol.

To setup IBSS over wlan0, run the following code, replacing `<ssid>`, `<freq>`, `<ipaddr>` with values of your choice. Connected machines must be on the same SSID, MHz frequency (channel) and subnet with unique IP addresses. For the list of frequencies and corresponding channels to choose from, see the [wiki](https://en.wikipedia.org/wiki/List_of_WLAN_channels) (2.4 Ghz or 5 Ghz for raspberry pi and most machines). Note that if you are SSH'ed into your machine via a router, this will terminate your connection.

```
# Stop NetworkManager and wpa_supplicant so they don't switch wifi back to managed mode
sudo systemctl stop NetworkManager
sudo systemctl stop wpa_supplicant

# Bring wlan0 interface down first in order to switch to IBSS mode
sudo ip link set wlan0 down
sudo iw wlan0 set type ibss
sudo ip link set wlan0 up

# Set the IBSS network SSID and frequency
sudo iw wlan0 ibss join <ssid> <freq>

# Assign the IBSS IP address
sudo ip addr add <ipaddr> dev wlan0
```

Altenatively, download and run the [ibss-setup.sh](./ibss_batman_scripts/ibss-setup.sh) shell script. Be sure to check (and change if needed) the `IFACE`, `SSID`, `FREQ` and `IPADDR` variables. 

To return wifi back to managed mode, run the following:
```
# Remove all ip addresses assigned to wlan0
sudo ip addr flush dev wlan0

# Return wlan0 to normal Wi-Fi client mode
sudo ip link set wlan0 down
sudo iw dev wlan0 set type managed
sudo ip link set wlan0 up

# Restart NetworkManager and wpa_supplicant since we stopped it earlier
sudo systemctl start NetworkManager
sudo systemctl start wpa_supplicant

# Give control back to normal networking services
sudo nmcli dev set "$IFACE" managed yes
```

Alternatively, run the [ibss-teardown.sh](./ibss_batman_scripts/ibss-teardown.sh) shell script.

# Usage with B.A.T.M.A.N.
Similarly, to use `rmw_zenoh` over BATMAN, simply set the endpoints in the zenoh router and session config files to the correct BATMAN IP addresses.

### Setting up BATMAN
Ensure `batctl`, the control tool for BATMAN, is installed:
```
sudo apt update
sudo apt install batctl -y
```

To setup BATMAN over wlan0, run the following code, replacing `<ssid>`, `<freq>`, `<ipaddr>` with values of your choice:
```
# Stop NetworkManager and wpa_supplicant so they don't switch wifi back to managed mode
sudo systemctl stop NetworkManager
sudo systemctl stop wpa_supplicant

# Load batman-adv
sudo modprobe batman-adv

# Clean the old config
sudo ip link set bat0 down
sudo batctl if del wlan0
sudo ip addr flush dev wlan0
sudo ip addr flush dev bat0

# Bring wlan0 interface down first in order to switch to IBSS mode
sudo ip link set wlan0 down
sudo iw wlan0 set type ibss
sudo ip link set wlan0 up

# Set the IBSS network SSID and frequency
sudo iw wlan0 ibss join <ssid> <freq>

# Add wlan0 to BATMAN
sudo batctl if add wlan0

# Bring bat0 up
sudo ip link set up dev bat0

# Assign the BATMAN IP address
sudo ip addr add <ipaddr> dev bat0
```

Altenatively, download and run the [ibss-batman-setup.sh](./ibss_batman_scripts/ibss-batman-setup.sh) shell script. Be sure to check (and change if needed) the `IFACE`, `SSID`, `FREQ` and `IPADDR` variables. 

To return wifi to managed mode, run the following:
```
# Stop BATMAN virtual interface
sudo ip link set bat0 down

# Detach wlan0 from BATMAN
sudo batctl if del wlan0

# Clear IPs from BATMAN and Wi-Fi interfaces
sudo ip addr flush dev bat0
sudo ip addr flush dev wlan0

# Return wlan0 to normal Wi-Fi client mode
sudo ip link set wlan0 down
sudo iw dev wlan0 set type managed
sudo ip link set wlan0 up

# Give control back to normal networking services
sudo systemctl start NetworkManager
sudo systemctl start wpa_supplicant
sudo nmcli dev set wlan0 managed yes
```

Alternatively, run the [ibss-batman-teardown.sh](./ibss_batman_scripts/ibss-batman-teardown.sh) shell script.

Useful batctl commands:
```
# See direct neighbours
sudo batctl neighbors

# See all reachable hosts, including those reachable by multihop
sudo batctl originators

```
