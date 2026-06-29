# Overview
The demo runs the demo talker and listener nodes from [demo_nodes_cpp](https://index.ros.org/p/demo_nodes_cpp/) using [rmw_zenoh](https://github.com/ros2/rmw_zenoh) as middleware. It uses 2 Raspberry Pi's on the same network, running ROS2 Kilted with Docker, but should also work for any 2 machines on the same network.

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
When opening any new terminal, do the following:

- Source ROS. If you built rmw_zenoh from source in your workspace, then source the `setup.bash` from the workspace instead.
```
source opt/ros/kilted/setup.bash
```

- Configure ROS to use rmw_zenoh for middleware:
```
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
```

Zenoh supports multiple communication models. See their [docs](https://zenoh.io/docs/getting-started/deployment) for more info. These models are configured by simply changing the parameters in the router and session config files. The default config files give example configurations, and can be found at `/opt/ros/kilted/share/rmw_zenoh_cpp/config/`. If instead of the binaries, rmw_zenoh was built from source in your workspace, the default config files are at `/path/to/your/workspace/src/rmw_zenoh/rmw_zenoh_cpp/config/`.

To change the parameters from the defaults, point rmw_zenoh to the modified config files:
```
export ZENOH_ROUTER_CONFIG_URI=path/to/my/config/file/directory/my_router_config.json5
export ZENOH_SESSION_CONFIG_URI=path/to/my/config/file/directory/my_session_config.json5
```

### 1. Two routers with clients
Discovery and comms are done only through the routers. 

Machine 1:
- router
- talker client node

Machine 2: 
- router
- listener client node

We configure the routers on both machines to connect to each other, and listen to each other on port 7447. With this router-client configuration, there is no scouting involved, so we set multicast and gossip to false.

Machine 1 router config:
```
{
    mode: "router",
    connect: {
        endpoints: ["tcp/<Machine 2 IP>:7447"]
    },
    listen: {
        endpoints: ["tcp/0.0.0.0:7447"]
    },
    scouting: {
        multicast: {
            enabled: false
        }
    },
}
```

Machine 2 router config:
```
{
    mode: "router",
    connect: {
        endpoints: ["tcp/<Machine 1 IP>:7447"]
    },
    listen: {
        endpoints: ["tcp/0.0.0.0:7447"]
    },
    scouting: {
        multicast: {
            enabled: false
        }
    }
}
```

Since no peer to peer communication is needed, we run the talker and listener nodes in client mode. Each client node connects to the router on the same machine, i.e. localhost address `127.0.0.1`. Machine 1 and Machine 2 session configs:
```
{
    mode: "client",
    connect: {
        endpoints: ["tcp/127.0.0.1:7447"]
    },
    listen: {
        endpoints: []
    },
    scouting: {
        multicast: {
            enabled: false
        }
    },
    transport: {
        shared_memory: {
            enabled: false
        }
    }
}
```

Remember to point rmw_zenoh to the modified config files for both machines:
```
export ZENOH_ROUTER_CONFIG_URI=path/to/my/config/file/directory/my_router_config.json5
export ZENOH_SESSION_CONFIG_URI=path/to/my/config/file/directory/my_session_config.json5
```

Start the routers on both machines:
```
ros2 run rmw_zenoh_cpp rmw_zenohd
```

Start the talker on Machine 1:
```
ros2 run demo_nodes_cpp talker
```

Start the listener on Machine 2:
```
ros2 run demo_nodes_cpp listener
```

Check that the published messages are in sync on the talker and listener.

### 2. One router with clients
Actually 2 routers are redundant, since Machine 2 can access Machine 1's router directly on the same network. 

Machine 1:
- router
- talker client node

Machine 2:
- listener client node

We can use the same Machine 1 router config file as above, but we no longer need to initiate any connection like we did with the second router in the previous configuration, just need to listen to the talker and listener nodes which will initiate the connection.
```
{
    mode: "router",
    connect: {
        endpoints: []
    },
    listen: {
        endpoints: ["tcp/0.0.0.0:7447"]
    },
    scouting: {
        multicast: {
            enabled: false
        }
    }
}
```

No change to the Machine 1 session config file, since the talker still connects to the router on the same machine as in the previous configuration:

```
{
    mode: "client",
    connect: {
        endpoints: ["tcp/127.0.0.1:7447"]
    },
    listen: {
        endpoints: []
    },
    scouting: {
        multicast: {
            enabled: false
        }
    },
    transport: {
        shared_memory: {
            enabled: false
        }
    }
}
```

For Machine 2, the session should connect to Machine 1's router instead, since there is no longer a router on Machine 2:
```
{
    mode: "client",
    connect: {
        endpoints: ["tcp/<Machine 1 IP>:7447"]
    },
    listen: {
        endpoints: []
    },
    scouting: {
        multicast: {
            enabled: false
        }
    },
    transport: {
        shared_memory: {
            enabled: false
        }
    }
}
```

Start the routers on just Machine 1:
```
ros2 run rmw_zenoh_cpp rmw_zenohd
```

Start the talker on Machine 1:
```
ros2 run demo_nodes_cpp talker
```

Start the listener on Machine 2:
```
ros2 run demo_nodes_cpp listener
```

Check that the published messages are in sync on the talker and listener.

### 3. One router with gossip sccouting
The router on Machine 1 is only used for discovery. The router allows the talker and listener nodes to discover each other via gossip scouting, after which the talker and listener nodes have peer to peer comms without the router.

We set gossip to true for the Machine 1 router config:
```
{
    mode: "router",
    connect: {
        endpoints: []
    },
    listen: {
        endpoints: ["tcp/0.0.0.0:7447"]
    },
    scouting: {
        multicast: {
            enabled: false
        },
        gossip: {
            enabled:true
        }
    }
}
```

For Machine 1 session config, we set the mode to peer and set gossip to true. The session should auto-connect to peers (direct p2p communication) and routers (for discovery). Note for the listen endpoint, we use Machine 1's concrete LAN IP address instead of the wildcard address `0.0.0.0` because the peer on Machine 2 needs a reachable IP address. The listen endpoint is used to open the right port for listening, but for peer mode it is also used to advertise the correct ip address for other peers to connect to. We also listen on port 7448 since the router is already using port 7447. Machine 1 session config: 
```
{
    mode: "peer",
    connect: {
        endpoints: ["tcp/127.0.0.1:7447"]
    },
    listen: {
        endpoints: ["tcp/<Machine 1 IP>:7448"]
    },
    scouting: {
        multicast: {
            enabled: false
        },
        gossip: {
            enabled: true,
            autoconnect: ["peer", "router"]
        }
    },
    transport: {
        shared_memory: {
            enabled: false
        }
    }
}
```

Likewise for the listener peer on Machine 2, we listen on the concrete LAN IP, and continue to connect to the Machine 1 router for discovery. Machine 2 session config:
```
{
    mode: "peer",
    connect: {
        endpoints: ["tcp/<Machine 1 IP>:7447"]
    },
    listen: {
        endpoints: ["tcp/<Machine 2 IP>:7448"]
    },
    scouting: {
        multicast: {
            enabled: false
        },
        gossip: {
            enabled: true,
            autoconnect: ["peer", "router"]
        }
    },
    transport: {
        shared_memory: {
            enabled: false
        }
    }
}
```
Start the router on Machine 1:
```
ros2 run rmw_zenoh_cpp rmw_zenohd
```

Start the talker on Machine 1:
```
ros2 run demo_nodes_cpp talker
```

Start the listener on Machine 2:
```
ros2 run demo_nodes_cpp listener
```

Check that the published messages are in sync on the talker and listener. Then terminate the router on Machine 1 and check that the published messages persist.

### 4. No routers with multicast scouting
We use multicast scouting, so both the discovery and comms are completely P2P. 

We do not set any connect endpoints, as the peers will auto connect. Just set the address and port to listen on. Machine 1 session config:
```
{
    mode: "peer",
    connect: {
        endpoints: []
    },
    listen: {
        endpoints: ["tcp/<Machine 1 IP>:7447"]
    },
    scouting: {
        multicast: {
            enabled: true,
            autoconnect: ["peer"]
        },
        gossip: {
            enabled: false
        }
    },
    transport: {
        shared_memory: {
            enabled: false
        }
    }
}
```

Machine 2 session config:
```
{
    mode: "peer",
    connect: {
        endpoints: []
    },
    listen: {
        endpoints: ["tcp/<Machine 2 IP>:7447"]
    },
    scouting: {
        multicast: {
            enabled: true,
            autoconnect: ["peer"]
        },
        gossip: {
            enabled: false
        }
    },
    transport: {
        shared_memory: {
            enabled: false
        }
    }
}
```

Start the talker on Machine 1:
```
ros2 run demo_nodes_cpp talker
```

Start the listener on Machine 2:
```
ros2 run demo_nodes_cpp listener
```

Check that the published messages are in sync on the talker and listener without the need for a router.

# Usage with IBSS
To use `rmw_zenoh` over IBSS, simply set the endpoints in the zenoh router and session config files to the correct IBSS IP addresses.

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

Altenatively, download and run the [ibss-setup.sh](scripts/ibss-setup.sh) shell script. Be sure to check (and change if needed) the `IFACE`, `SSID`, `FREQ` and `IPADDR` variables. 

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

Alternatively, run the [ibss-teardown.sh](scripts/ibss-teardown.sh) shell script.

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

Altenatively, download and run the [ibss-batman-setup.sh](scripts/ibss-batman-setup.sh) shell script. Be sure to check (and change if needed) the `IFACE`, `SSID`, `FREQ` and `IPADDR` variables. 

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

Alternatively, run the [ibss-batman-teardown.sh](scripts/ibss-batman-teardown.sh) shell script.