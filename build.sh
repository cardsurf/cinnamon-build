#!/bin/bash

# A script that builds .deb packages from source code and installs them.
# Source code repositories need to have "debian" directory with structure that conforms to Debian package requirements. 
# For details see: https://www.debian.org/doc/debian-policy/

# *********************************************************************************************************************
# ***********************************************Script configuration**************************************************
# *********************************************************************************************************************
base_url=""         # Base url of GitHub repositories to build
all_repositories=() # Names of GitHub repositories to build
branch=""           # Branch of GitHub repositories to build
base_sources=()     # Additional package sources in "/etc/apt/sources.list" file to search for when building depenencies
# *********************************************************************************************************************
# ********************************************Debian stable configuration**********************************************
# *********************************************************************************************************************
base_url="https://github.com/linuxmint"
all_repositories=("cjs" "flags" "xapps" "cinnamon-desktop" "cinnamon-translations" "cinnamon-menus" "cinnamon-session" "cinnamon-settings-daemon" "cinnamon-control-center" "cinnamon-screensaver" "muffin" "nemo" "Cinnamon")
branch="master"
base_sources=("deb http://deb.debian.org/debian sid main" "deb-src http://deb.debian.org/debian sid main")
# *********************************************************************************************************************
# *********************************************************************************************************************
# *********************************************************************************************************************





# Declare constants
base_path=$PWD
sources_file="/etc/apt/sources.list"
summary_file=${base_path}/"summary.log"
package_log="build.log"
all="all"
pad="********************************************************************************"
pad_length=80

# Declare variables
repositories=()

# Automatically split array elements in for loops on newline only
IFS=$'\n'

# Checks if array contains element
function contains() { 
item_find=$1
shift 1
array=("${@}")
result=0
for item in "${array[@]}"; do
    if [ "$item" == "$item_find" ]; then
        result=1
        break
    fi
done
echo $result
}

# Gets first string index in array that is equal to input string using case insensitive string comparsion
function get_index_insensitive() { 
item_find=$(echo "$1"| tr '[:upper:]' '[:lower:]')
shift 1
array=("${@}")
result=-1
for i in "${!array[@]}"; do
    item_lower=$(echo "${array[$i]}"| tr '[:upper:]' '[:lower:]')
    if [ "$item_lower" == "$item_find" ]; then
        result=$i
        break
    fi
done
echo $result
}

# Removes leading and trailing whitespaces from string
function trim() { 
str=$1
str=$(echo "$str" | sed 's/[[:space:]]*$//g')
str=$(echo "$str" | sed 's/^[[:space:]]*//g')
echo $str
}

# Appends formatted information about start of next script step  
function add_step() { 
step=$1
step=${step:0:$pad_length}
length=${#step}
if [ "$length" -lt "$pad_length" ]; then
    pad_both=$((pad_length-length))
    pad_left=$((pad_both/2))
    pad_right=$((pad_both-pad_left))
    step="${pad:0:$pad_left}$step${pad:0:$pad_right}"
fi
echo "$pad" | tee -a "$summary_file"
echo "$step" | tee -a "$summary_file"
echo "$pad" | tee -a "$summary_file"
}

# Writes non-empty string to file
function write_non_empty() { 
str=$1
file=$2
if [ -n "${str}" ]; then
    echo "$str" >> "$file"
fi
}





# Checks if script is run with sudo priviliges
function check_sudo {
    script_user=$(whoami)
    if [ "$script_user" != "root" ]; then
        echo "You need to run this script as root or with sudo."
        exit
    fi
}






# Reads GitHub repository names from command line arguments
function parse_parameters {

    # Read lowercase command line parameters to array
    input_repositories=("${@}")
    for i in "${!input_repositories[@]}"; do
        input_repositories[$i]=$(echo "${input_repositories[$i]}"| tr '[:upper:]' '[:lower:]')
    done

    # If input array is empty then the are no repositories to update
    if [ "${#input_repositories[@]}" -eq "0" ]; then
        echo "No parameters provided. Please pass GitHub repository names to build as command line arguments or \"all\" keyword to build all defined repositories." | tee -a "$summary_file"
        exit
    fi

    # If input array contains "all" parameter then update all repositories
    is_all=$(contains "$all" "${input_repositories[@]}")
    if [ "$is_all" -eq "1" ]; then
        echo "\"all\" parameter provided. Updating all repositories." | tee -a "$summary_file"
        repositories=("${all_repositories[@]}")

    # Otherwise update repositories provided in command line
    else 
        echo "Reading repository names from command line parameters." | tee -a "$summary_file"
        # Add repository names
        for input_repository in "${input_repositories[@]}"; do
            index=$(get_index_insensitive "$input_repository" "${all_repositories[@]}")

            # If repository name is defined
            if [ "$index" -ge "0" ]; then
                repository="${all_repositories[$index]}"
                added=$(contains "$repository" "${repositories[@]}")
                # If repository name has not been added
                if [ "$added" -eq "0" ]; then
                    # Add repository to update
                    repositories+=("$repository")
                fi
            else
                echo "Uncrecognized repository name \""$input_repository"\" has been skipped." | tee -a "$summary_file"
            fi
        done
    fi

    echo "The following repositories will be updated:" | tee -a "$summary_file"
    for repository in "${repositories[@]}"; do
        echo "- $repository" | tee -a "$summary_file"
    done
    echo "Number of repositories to update: ${#repositories[@]}" | tee -a "$summary_file"

    if [ "${#repositories[@]}" -eq "0" ]; then
        echo "[FAIL] No repositories to update."| tee -a "$summary_file"
        echo "Aborting build process." | tee -a  "$summary_file"
        exit
    fi
}






# Adds deb-src sources to /etc/apt/sources.list file
function update_sources {

    echo "Updating sources in $sources_file file ..." | tee -a "$summary_file"
    if [ -f "$sources_file" ]; then

        # Declare variables
        user_sources=()
        output_lines=()
        output_infos=()

        # Read file
        source_lines=($(cat $sources_file))

        # Remove comments and empty lines
        for source in "${source_lines[@]}"; do
            is_comment_empty=$(echo $source | gawk '{match($0, /#|^[[:cntrl:]]$/, matches); print matches[0]}' )
            # If there is no match
            if [ -z "${is_comment_empty}" ]; then
                # Add source definition
                user_sources+=("$source")
            fi
        done      

        # Add file sources and default sources
        sources=("${user_sources[@]}" "${base_sources[@]}")

        # Add deb and deb-src sources
        for source in "${sources[@]}"; do
            # Get source information
            info=$(echo $source | gawk '{match($0, /http.*/, matches); print matches[0]}' )

            # Add source information if it was not added
            exists=$(contains "$info" "${output_infos[@]}")
            if [ "$exists" -eq "0" ]; then
                output_infos+=("$info")
                output_lines+=("deb $info")
                output_lines+=("deb-src $info")
            fi
        done

        # If number of lines is greater then number of sources
        if [ "${#output_lines[@]}" -gt "${#user_sources[@]}" ]; then
            # Update sources
            printf "%s\n" "${output_lines[@]}" > $sources_file
            echo "Updated $sources_file with ${#output_lines[@]} sources." | tee -a "$summary_file"
            
            # Update package list
            echo "Updating package list ..." | tee -a "$summary_file"
            apt-get update 2>&1 | tee -a "$summary_file"
        else
            echo "File $sources_file has not been changed." | tee -a "$summary_file"
        fi
    else
       echo "[FAIL] File $sources_file does not exists." | tee -a "$summary_file"
       echo "Aborting build process." | tee -a  "$summary_file"
       exit
    fi
}







# Installs packages required to run script
function install_prerequisites { 

    # Read parameters
    repository=$1

    # Declare variables
    deb_path=${base_path}/${repository}

    # Move to .deb package directory
    cd "$deb_path"

    # Update package list
    echo "Updating package list ..." | tee -a "$summary_file"
    apt-get update 2>&1 | tee -a "$summary_file"

    # Install packages
    echo "Installing packages required to run script ..." | tee -a "$summary_file"
    DEBIAN_FRONTEND=noninteractive apt-get -y install git dpkg-dev gawk 2>&1 | tee -a "$summary_file"

    # Install old version of NetworkManager to prevent Cinnamon build from failing
    # Installation of this packages should be removed once it is fixed
    DEBIAN_FRONTEND=noninteractive apt-get -y install network-manager-dev libnm-util2 libnm-glib-dev gir1.2-networkmanager-1.0 libnma-dev gir1.2-nma-1.0 2>&1 | tee -a "$summary_file"
    apt-mark hold network-manager-dev libnm-util2 libnm-glib-dev gir1.2-networkmanager-1.0 libnma-dev gir1.2-nma-1.0
}







# Clones source code files from GitHub repository
function clone_repository { 
    
    # Read parameters
    repository=$1

    # Declare variables
    repository_path=${base_path}/${repository}/${repository}
    log_file=${base_path}/${repository}/${package_log}
    repostiory_url=${base_url}/${repository}".git"
    origin_branch="origin"/$branch
    output=""
    error=""

    # Create files
    touch "$log_file"
    error_file=$(mktemp)

    if [ ! -d $repository_path ]; then
        echo "Cloning \"$repository\" repository from GitHub ..." | tee -a "$log_file"
        git clone $repostiory_url $repository_path 2>&1 | tee -a "$log_file"
    else
        echo "Source code directory $repository_path exists." | tee -a "$log_file"
    fi

    # Move to repository path
    cd "$repository_path"

    # Check if local branch exists
    echo "Switching to build branch." | tee -a "$log_file"
    git show-ref --verify "refs/heads/$branch" 2>&1

    # If local branch exists
    if [ "$?" -eq "0" ]; then
        # Switch to local branch
        echo "Switching to local branch \"$branch\"." | tee -a "$log_file"
        output=$(git checkout -b $branch $origin_branch 2> "$error_file")
    else
        echo "[FAIL] Clone \"$repository\" repository. Remote branch \"$branch\" does not exists." | tee -a  "$summary_file" "$log_file"
        echo "Aborting build process." | tee -a  "$summary_file" "$log_file"
        exit
    fi

    if [ -n "${output}" ]; then
        echo "$output" | tee -a  "$log_file"
    fi
    if [ -n "${error}" ]; then
        echo "$error"| tee -a  "$log_file"
    fi
    rm "$error_file"

    # Check if there was error while switching to build branch
    if [ -n "${error}" ]; then
        echo "[FAIL] Clone \"$repository\" repository. Error while switching to build branch." | tee -a  "$summary_file" "$log_file"
        echo "Aborting build process." | tee -a  "$summary_file" "$log_file"
        exit
    fi

    echo "[SUCCESS] Clone \"$repository\" repository." | tee -a "$summary_file" "$log_file"
}







# Builds .deb packages from source code files
function build_deb { 
    
    # Read parameters
    repository=$1

    # Declare variables
    deb_path=${base_path}/${repository}
    repository_path=${base_path}/${repository}/${repository}
    log_file=${base_path}/${repository}/${package_log}
    output=""
    error=""
    unprocessed_dependencies=()
    processed_dependencies=()

    # Create files
    touch "$log_file"
    error_file=$(mktemp)
    
    # Move to source code files directory
    cd "$repository_path"

    # Install package dependencies
    echo "Installing \"$repository\" package dependencies ..." | tee -a "$log_file"
    apt-get -y build-dep "${repository}" 2>&1 | tee -a "$log_file"

    # Check package build depencencies
    echo "Checking \"$repository\" build dependencies ..." | tee -a "$log_file"
    output=$(dpkg-checkbuilddeps 2> "$error_file")

    # Get missing build dependencies
    error=$(tail -n 1 "$error_file")
    missing=$(echo $error | gawk '{match($0, /Unmet build dependencies:(.*)/, matches); print matches[1]}') # Get substring after "Unmet build dependencies:"
    unprocessed_dependencies=($(echo "$missing" | sed 's/ [=><().0-9 ]*/\n/g'))                             # Convert strings separated with spaces and version numbers to array

    # Write missing dependencies to log
    write_non_empty "$output" "$log_file"
    write_non_empty "$error" "$log_file"
    rm "$error_file"

    # If there are missing dependencies required to install .deb package then install them
    if [ "${#unprocessed_dependencies[@]}" -gt "0" ]; then
        echo "Installing missing build dependencies:$missing for package: \"$repository\"" | tee -a "$log_file"
        # Install missing dependencies
        for i in "${!unprocessed_dependencies[@]}"; do
            dependency=$(trim "${unprocessed_dependencies[$i]}")
            echo "[$(($i + 1))/${#unprocessed_dependencies[@]}] Installing missing dependency \"$dependency\" ... " | tee -a "$log_file"
            DEBIAN_FRONTEND=noninteractive apt-get -y install "${dependency}" 2>&1 | tee -a "$log_file"
        done
    fi

    # Build package
    echo "Building \"$repository\" package ..." | tee -a "$log_file"
    dpkg-buildpackage 2>&1 | tee -a "$log_file"
    echo "Finished building \"$repository\" package." | tee -a "$log_file"

    # Check if there are any output .deb files 
    is_deb=$(ls "${deb_path}" | grep deb)
    if [ -z "${is_deb}" ]; then
        echo "[FAIL] Build \"$repository\" package. No output .deb files found." | tee -a  "$summary_file" "$log_file"
        echo "Aborting build process." | tee -a  "$summary_file" "$log_file"
        exit
    else
        echo "[SUCCESS] Build of \"$repository\" package. Output .deb files found." | tee -a "$summary_file" "$log_file"
    fi
}







# Installs .deb packages
function install_deb { 
    
    # Read parameters
    repository=$1

    # Declare variables
    deb_path=${base_path}/${repository}
    deb_files=${deb_path}/"*deb"
    log_file=${base_path}/${repository}/${package_log}
    output=""
    error=""
    unprocessed_dependencies=()
    processed_dependencies=()

    # Check if there are any packges to install
    deb_names=$(ls "${deb_path}" | grep deb)
    if [ -z "${deb_names}" ]; then
        echo "[FAIL] No .deb files found to install \"$repository\" package." | tee -a "$log_file"
        echo "Aborting build process." | tee -a  "$summary_file" "$log_file"
        exit
    else
        # Print .deb package names to install
        echo "The following output .deb files will be installed for \"$repository\" package:" | tee -a "$summary_file" "$log_file"
        deb_names=($(echo "$deb_names" | sed 's/ /\n/g') ) # Split package names on spaces to array
        for deb_name in "${deb_names[@]}"; do
            echo "- $deb_name" | tee -a "$summary_file" "$log_file"
        done
        echo "Number of .deb files to install: ${#deb_names[@]}" | tee -a "$summary_file" "$log_file"

        # Create files
        touch "$log_file"
        error_file=$(mktemp)
        
        # Move to source code files directory
        cd "$repository_path"

        # Install package
        echo "Installing \"$repository\" package ... $deb_path" | tee -a "$log_file"
        output=$(dpkg -i $deb_files 2> "$error_file")

        # Get missing packages
        error=$(cat "$error_file")
        missing=$(echo $error | gawk '{match($0, /Package (.*) is not installed/, matches); print matches[1]}') # Get non-installed package names
        unprocessed_dependencies=($(echo "$missing" | sed 's/is not installed/\n/g') )                          # Split missing package information on "is not installed" substrings to array
        # Get names of missing packages
        for i in "${!unprocessed_dependencies[@]}"; do
           dependency=$(trim "${unprocessed_dependencies[$i]}")                                                                 # Remove leading and trailing whitespaces
           unprocessed_dependencies[$i]=$(echo "$dependency" | gawk '{match($0, /[[:graph:]]*$/, matches); print matches[0]}')  # Get missing package name
        done

        # If there are missing packages required to install .deb package then install them
        while [ "${#unprocessed_dependencies[@]}" -gt "0" ]
        do
            echo "Installing missing packages: $missing required to install package: \"$repository\"" | tee -a "$log_file"
            write_non_empty "$output" "$log_file"
            write_non_empty "$error" "$log_file"
            rm "$error_file"
            error_file=$(mktemp)
            output=""
            error=""

            # Install missing packages
            for i in "${!unprocessed_dependencies[@]}"; do
                dependency="${unprocessed_dependencies[$i]}"
                # Install missing package dependencies
                echo "[$(($i + 1))/${#unprocessed_dependencies[@]}] Installing dependencies of missing package \"$dependency\" ..." | tee -a "$log_file"
                apt-get -y build-dep "${dependency}" 2>&1 | tee -a "$log_file"
                # Install missing package
                echo "[$(($i + 1))/${#unprocessed_dependencies[@]}] Installing missing package \"$dependency\" ... " | tee -a "$log_file"
                DEBIAN_FRONTEND=noninteractive apt-get -y install "${dependency}" 2>&1 | tee -a "$log_file"
                processed_dependencies+=("$dependency")
            done

            # Install package
            echo "Installing \"$repository\" package ... $deb_path" | tee -a "$log_file"
            output=$(dpkg -i $deb_files 2> "$error_file")

            # Get missing packages
            error=$(cat "$error_file")
            missing=$(echo $error | gawk '{match($0, /Package (.*) is not installed/, matches); print matches[1]}') # Get non-installed package names
            dependencies=($(echo "$missing" | sed 's/is not installed/\n/g') )                                      # Split missing package information on "is not installed" substrings to array
           
            # Get names of missing packages
            for i in "${!dependencies[@]}"; do
               dependency=$(trim "${dependencies[$i]}")                                                                 # Remove leasing and trailing whitespaces
               dependencies[$i]=$(echo "$dependency" | gawk '{match($0, /[[:graph:]]*$/, matches); print matches[0]}')  # Get missing package name
            done

            # Add not installed missing packages
            unprocessed_dependencies=()
            for dependency in "${dependencies[@]}"; do
                processed=$(contains "$dependency" "${processed_dependencies[@]}")
                # If missing package was not installed then add it for installation
                if [ "$processed" -eq "0" ]; then
                    unprocessed_dependencies+=("$dependency")
                fi
            done
     done

        write_non_empty "$output" "$log_file"
        write_non_empty "$error" "$log_file"
        rm "$error_file"
    fi
}







# Verifies installation of .deb packages
function verify_installation { 

        # Read parameters
        repository=$1

        # Declare variables
        deb_path=${base_path}/${repository}
        log_file=${base_path}/${repository}/${package_log}

        echo "Verifying installation for \"$repository\" package ..."| tee -a "$log_file"

        # Get installed package names
        deb_names=$(ls "${deb_path}" | grep deb)
        deb_names=($(echo "$deb_names" | sed 's/_.*\.deb/\n/g') )       
        
        # If there are no .deb packages then build failed
        if [ "${#deb_names[@]}" -eq "0" ]; then
            echo "[FAIL] Install \"$repository\" package. No .deb files found to install package."| tee -a "$summary_file" "$log_file"
            echo "Aborting build process." | tee -a  "$summary_file"
            exit
        fi

        # Check if .deb packages are installed
        for i in "${!deb_names[@]}"; do
            output=""
            error=""
            error_file=$(mktemp)

            # Check if .deb package is installed
            name="${deb_names[$i]}"
            echo "[$(($i + 1))/${#deb_names[@]}] Verifing \"$name\" result package installation ..."| tee -a "$log_file"
            output=$(dpkg -s $name 2> "$error_file")
            write_non_empty "$output" "$log_file"
            write_non_empty "$error" "$log_file"
            rm "$error_file"

            # If there was error then abort build process
            if [ -n "${error}" ]; then
                echo "[FAIL] Verify  \"$repository\" package installation. Result \"$name\" package is not installed." | tee -a  "$summary_file" "$log_file"
                echo "Aborting build process." | tee -a  "$summary_file" "$log_file"
                exit
            else
                echo "[SUCCESS] Verify \"$repository\" package installation. Result \"$name\" package is installed." >> "$summary_file"
            fi
        done

        echo "[SUCCESS] Install \"$repository\" package." | tee -a "$summary_file" "$log_file"
}







# Removes .deb packages
function remove_deb { 

    # Read parameters
    repository=$1

    # Declare variables
    deb_path=${base_path}/${repository}
    log_file=${base_path}/${repository}/${package_log}

    # Create files
    touch "$log_file"

    # Move to deb package directory
    cd "$deb_path"

    # Remove packages
    echo "Removing $repository\" packages ..." | tee -a "$log_file"
    rm -f *.deb
}






# Runs script
function run {

    # Check permissions
    check_sudo

    # Read parameters
    parameters=("${@}")

    # Create files
    > "$summary_file"

    # Run script
    add_step "Parsing parameters"
    parse_parameters "${parameters[@]}"

    # Install packages required to run script
    add_step "Installing prerequisties"
    install_prerequisites

    # Update package sources
    add_step "Updating sources"
    update_sources

    # Install package from source code
    for repository in "${repositories[@]}"; do

        add_step "Installing $repository package"
        echo "Started installing \"$repository\" package from source code." | tee -a "$summary_file"

        # Declare variables
        deb_path=${base_path}/${repository}
        log_file=${base_path}/${repository}/${package_log}

        # Create directories
        mkdir -p "$deb_path"

        # Create files
        >"$log_file"

        # Clone GtiHub repository
        clone_repository "$repository"

        # Build package from source code
        build_deb "$repository"

        # Install .deb packages
        install_deb "$repository"

        # Verify installation of .deb packages
        verify_installation "$repository"

        #Remove .deb packages
        remove_deb "$repository"
        echo "Build log has been saved to file: $log_file." | tee -a "$summary_file"
        echo "Finished installing \"$repository\" package from source code." | tee -a "$summary_file"

    done
}





# Run script
run $@

