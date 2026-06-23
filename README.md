# Overview
The demo uses 2 Raspberry Pi's on the same network, and runs ROS2 Kilted with Docker. It should work for any 2 machines on the same network.

# Setup

Ensure [Docker](https://docs.docker.com/engine/install/) is installed 

Pull any of the [official ROS2 images](https://hub.docker.com/r/osrf/ros) and run a container interactively in host mode. This demo uses `ros:kilted-ros-core` and names the container "demo":
```
docker create -it --name demo --network host ros:kilted-ros-core &&
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
The following 
Configure the