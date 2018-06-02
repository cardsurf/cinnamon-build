# Cinnamon build
A script that installs the latest version of Cinnamon from source code

## Configuration
Configuration parameters are declared and described at the beggining of the `build.sh` script.

## Parameters
The `build.sh` script takes GitHub repository names to build and install as parameters.  
The `all` parameter makes the `build.sh` script to build and install all of configured repositories.

## Logs
The `build.sh` script saves installation progress into two kind of logs:
* `summary.log` - stores overall installation progress
* `[repository]\build.log`- stores detailed progress of package build and installation

## Docker installation
To install the latest version of Cinnamon from source code on Debian Stable in a Docker container:
1. Copy the `build.sh` script to `$HOME/cinnamon_build` folder
2. Run Docker image of Debian Stable:  
   `docker run -it -v $HOME/cinnamon_build:/cinnamon_build/ debian:stable /bin/bash`
3. Run the script  
   ```
   cd /cinnamon_build
   ./build.sh all
   ```
## VirtualBox installation
To install the latest version of Cinnamon from source code on Debian Stable in a VirtualBox virtual machine:
1. Install Debian Stable in a VirtualBox virtual machine:  
   At the `Software selection` step uncheck all of the options
2. Copy the `build.sh` script to `/cinnamon_build` folder on a virtual machine without installing Guest Additions.  
   A USB drive or an .iso image can be used to copy the `build.sh` script to a virtual machine without installing Guest Additions. 
3. Run the script  
   ```
   su - root
   cd /cinnamon_build
   ./build.sh all
   ```
