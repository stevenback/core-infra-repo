#!/bin/bash
PFVERSION=9.3.1
PF_SIZE_REQ=1024 
PF_TMP_SIZE_REQ=200
TMP_DIR=/tmp/ping-tmp/
SERVICE_OUTPUT="service-output.txt"
# PF Download Base URL
BASE_DL_URL="https://s3.amazonaws.com/pingone/public_downloads/pingfederate/"
CHOSEN_PORTS=()

lowercase(){
    echo "$1" | sed "y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/"
}

no_help_msg="No help available for this field."

# Prereq
function prereq () {
path_to_executable=$(which $1 2> /dev/null)
 if [[ ! -x "$path_to_executable" ]]; then
   if [ -f /etc/redhat-release ] ; then
    echo Installing $1
    yum -q install $1
   fi
   if [ -f /etc/debian_version ] ; then
    echo Installing $1
    apt-get install $1
   fi
 fi
path_to_executable=$(which $1 2> /dev/null)
 if [[ ! -x "$path_to_executable" ]]; then
    echo Unable to install $1, please install $1
    exit 1
 fi
}

#######################################
# Executes the service-installer.jar tool
#
# Note: JAVA_HOME must be set before calling this function
#
# Args: 1) the directory containing service-installer.jar
# Args: 2 - N) arguments to service-installer.jar
#######################################
function service_tool()
{
   local TOOL_DIR="$1"
   shift
   "${JAVA_HOME}/bin/java" -jar "${TOOL_DIR}/service-installer.jar" $@ 2>&1 | tee ${TMP_DIR}/${SERVICE_OUTPUT}
}

#######################################
# Prints a failure message, then exits with code 1
#
# Args: 1) failure message
#######################################
function die()
{
    local MSG=$1
    echo " "
    echo "${MSG}"
    echo " "
    exit 1
}

#######################################
# Prompts the user for a boolean (y/n) input.
#
# Args: 1) the prompt message to be displayed
#       2) help text to display if '?' is entered (optional, may be '')
#       3) the default value to use if the user doesn't enter one (optional, may be '')
#
# Upon return:
# The global ${USER_CONFIRMED} variable will be set to "yes" if the user confirmed,
# otherwise it will be set to an empty string.
# This allows for the test:  if [[ ${USER_CONFIRMED} ]]
#######################################
declare USER_CONFIRMED

function confirm()
{
    local message="$1"
    local help="$2"
    local default="$3"

    while true; do
        prompt "${message} (y/n)" "${help}" "${default}"
        if [[ ${USER_INPUT} =~ ^\s*[yY]([eE][sS])?\s*$ ]]; then
            USER_CONFIRMED="yes"
            return
        elif [[ ${USER_INPUT} =~ ^\s*[nN][oO]?\s*$ ]]; then
            USER_CONFIRMED=""
            return
        else
            printf "\nInvalid input. Please enter 'y' or 'n', or '?' for help.\n\n"
        fi
    done
}

#######################################
# Prompts the user for input.
#
# Args: 1) the prompt message to be displayed
#       2) help text to display if '?' is entered (optional, may be '')
#       3) the default value to use if the user doesn't enter one (optional, may be '')
#
# Upon return:
# The global ${USER_INPUT} variable will be set with the value entered by the user.
#######################################
declare USER_INPUT

function prompt()
{
    local message="$1"
    local help="$2"
    local default="$3"

    if [[ -z ${help} ]]; then
        help="[ Help not available ]"
    fi

    if [[ ! -z ${default} ]]; then
        message="${message} [${default}]"
    fi

    input=""
    while [[ -z "${input}" ]]; do
        read -e -p "${message} " input
        if [[ ${input} =~ ^\s*\?\s*$ ]]; then
            input=""
            printf "\n${help}\n\n"
        elif [[ ${input} =~ ^\s*$ ]]; then
            input=${default}
        fi
    done
    USER_INPUT="${input}"
}

#######################################
# Checks to see if SELinux is installed and enforcing (in conjunction with systemd).
# If so, warns the user about possible problems and prompts to continue.
#######################################
function checkSELinux()
{
    # Check for the presence of systemd
    if [ $(readlink /sbin/init | grep systemd) ]; then

        # Check to see if SELinux policy is being enforced
        if [ $(getenforce | grep Enforcing) ]; then

            echo ""
            echo "!! WARNING !!"
            echo "It appears that SELinux policy is being enforced."
            echo "Due to a known issue with systemd, this could prevent the PingFederate service from being properly installed."
            echo "Temporarily disabling SELinux before continuing will avoid this problem."
            echo ""

            confirm "Do you want to continue with installation?" \
                    "Enter 'y' to continue, despite potential problems (or after making changes)."
            if [[ ! ${USER_CONFIRMED} ]]; then
                die "Installation aborted."
            fi
        fi
    fi
}

# Mode selection
function mode_selection () {
echo "Please choose which mode you'd like PingFederate to operate in."
PS3='Please enter your choice: '
options=("Standalone" "Clustered Admin Node" "Clustered Runtime Node" "Quit Installer")
select opt in "${options[@]}"
do
    case $opt in
        "Standalone")
	    pfmode="STANDALONE"
	    pfmodetxt="Standalone"
	    pfmodetxt2="Standalone mode"
	    pfmodetxt3="This will be your only PingFederate node that will operate independently."
	    break
            ;;
        "Clustered Admin Node")
            pfmode="CLUSTERED_CONSOLE"
	    pfmodetxt="Clustered Admin Node"
	    pfmodetxt2="Clustered Admin mode"
	    pfmodetxt3="This will be one of several nodes in a cluster that will host the admin console. Only one node in the cluster can operate the admin console."
            break
            ;;
        "Clustered Runtime Node")
            pfmode="CLUSTERED_ENGINE"
	    pfmodetxt="Clustered Runtime Node"
	    pfmodetxt2="Clustered Runtime mode"
	    pfmodetxt3="This will be one of several nodes in a cluster that will not host the admin console."
            break
            ;;
        "Quit Installer")
            exit 0
            ;;
        *) echo invalid option;;
    esac
done

echo " "
echo "You've selected ${pfmodetxt2}."
echo $pfmodetxt3
read -e -p "Would you like to continue? (y/n) " -i "y" confirmation
if [[ $confirmation =~ ^[Nn]$ ]]; then
  mode_selection
fi
}

#Functions
function cleanup()
{
    if [ -f ${TMP_DIR}/PF_JAVA_HOME.tmp ]; then
        rm ${TMP_DIR}/PF_JAVA_HOME.tmp
    fi
    if [ -f ${TMP_DIR}/${SERVICE_OUTPUT} ]; then
        rm ${TMP_DIR}/${SERVICE_OUTPUT}
    fi
}
trap cleanup EXIT

function get_port () {
help=$1_help
read -e -p "Enter Port (or ?): " -i "$2" "$1"
  if [[ ${!1} = *\?* || ${!1} = *help* ]]; then
    echo " "
    echo "${!help}"
    echo " "
    get_port $1 $2 $3
  fi
  if (( "$1" != -1 && ("$1" <= 1023 || "$1" >= 65536) )); then
    echo Invalid port, available options are -1 for disabled or the port range 1024-65535
    get_port $1 $2 $3
  fi

  if isPortAlreadyChosen $3 ${!1} ; then
    echo "The port '${!1}' has already been selected in the installer. Please choose a different port to avoid conflicts."
    get_port $1 $2 $3
  fi

  if [[ ! -x "${3}" ]]; then
    test_port ${3} ${!1}
    if [ $? -eq 0 ]; then
      echo "The port ${!1} is not available on the interface ${3}. Please select an available port."
      read -e -p "Would you like to continue? (y/n) " -i "y" confirmation
  	  if [[ ! $confirmation =~ ^[Yy]$ ]]; then
  	    get_port $1 $2 $3
  	  fi
    fi
  fi
}

function get_port_no_neg1 () {
help=$1_help
read -e -p "Enter Port: " -i "$2" "$1"
  if [[ ${!1} = *\?* || ${!1} = *help* ]]; then
    echo " "
    echo "${!help}"
    echo " "
    get_port_no_neg1 $1 $2 $3
  fi
  if (( "$1" <= 1023 || "$1" >= 65536 )); then
    echo Invalid port, valid port range is 1024-65535
    get_port_no_neg1 $1 $2 $3
  fi

  if isPortAlreadyChosen $3 ${!1} ; then
    echo "The port '${!1}' has already been selected in the installer. Please choose a different port to avoid conflicts."
    get_port_no_neg1 $1 $2 $3
  fi

  if [[ ! -x "${3}" ]]; then
    test_port ${3} ${!1}
    if [ $? -eq 0 ]; then
      echo "The port ${!1} is not available on the interface ${3}. Please select an available port."
      read -e -p "Would you like to continue? (y/n) " -i "y" confirmation
  	  if [[ ! $confirmation =~ ^[Yy]$ ]]; then
  	    get_port_no_neg1 $1 $2 $3
  	  fi
    fi
  fi
}


function get_port_and_zero () {
read -e -p "Enter Port (or ?): " -i "$2" "$1"
random_port=0
case "${!1}" in
  *help* | *\?*)
    help=$1_help
    echo " "
    echo "${!help}"
    echo " "
    get_port_and_zero $1 $2 $3
    ;;
  -1)
    echo 'Invalid port, available options are 0 or unset for random or range 1024-65535.'
    get_port_and_zero $1 $2 $3
    ;;
  '' | 0)
    echo "A random port will be assigned."
    random_port=1
    ;;
  *[0-9])
    while ( [[ ! ${!1} =~ $number ]] || [[ ${!1} -ge 65536 ]] || [[ ${!1} -lt 1024 ]] ); do
      echo 'Invalid port, available options are 0 or unset for random or range 1024-65535.'
      get_port_and_zero $1 $2 $3
    done
    ;;
  *)
     echo 'Invalid port, available options are 0 or unset for random or range 1024-65535.'
     get_port_and_zero $1 $2 $3
  ;;
esac

  if isPortAlreadyChosen $3 ${!1} ; then
    echo "The port '${!1}' has already been selected in the installer. Please choose a different port to avoid conflicts."
    get_port_and_zero $1 $2 $3
  fi

  if [[ ! -x "${3}" ]]; then
    if [[ ${random_port} -eq 0 ]] ; then
      test_port ${3} ${!1}
      if [ $? -eq 0 ]; then
        echo "The port ${!1} is not available on the interface ${3}. Please select an available port."
        read -e -p "Would you like to continue? (y/n) " -i "y" confirmation
  	    if [[ ! $confirmation =~ ^[Yy]$ ]]; then
  	      get_port_and_zero $1 $2 $3
  	    fi
      fi
    fi
  fi
}

# nc command changed major versions between RHEL 6 and 7, so need different options to accomplish port testing.
function test_port() {
    rpm -q nmap-ncat > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      nc --sh-exec "exit 0" ${1} ${2} > /dev/null 2>&1
      return $?
    fi

    rpm -q nc > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      nc -z ${1} ${2} > /dev/null 2>&1
      return $?
    fi

    # If we still dont have nc/nmap installed, then just assume the port is available.
    return 1
}


function get_address () {
read -e -p "Enter IP Address (or ?): " -i "$2" "$1"
  while [[ ${!1} = *\?* || ${!1} = *help* ]]; do
    help=$1_help
    echo " "
    echo "${!help}"
    echo " "
    get_address $1 $2
    echo " "
  done
}


function get_address_and_0000 () {
read -e -p "Enter IP Address (or ?): " -i "$2" "$1"
  while [[ ${!1} = *\?* || ${!1} = *help* ]]; do
    help=$1_help
    echo " "
    echo "${!help}"
    echo " "
    get_address_and_0000 $1 $2
    echo " "
  done
  while [ -z "${!1}" ]; do
    echo "Required field"
    get_address_and_0000 $1 $2
  done
}


function get_hosts () {
read -e -p "Enter Hosts (or ?): " -i "$2" "$1"
  while [[ ${!1} = *\?* || ${!1} = *help* ]]; do
    help=$1_help
    echo " "
    echo "${!help}"
    echo " "
    read -e -p "Enter Hosts (or ?): " -i "$2" "$1"
    echo " "
  done
}


function get_node_index () {
read -e -p "Enter the unique index number for this cluster node (or ?): " -i "" pf_cluster_node_index

case "$pf_cluster_node_index" in
  *help* | *\?*)
    echo " "
    echo $pf_cluster_node_index_help
    echo " "
    get_node_index
    ;;
  *[0-9])
    while ( [[ ! $pf_cluster_node_index =~ $number ]] || [[ $pf_cluster_node_index -ge 65536 ]] || [[ $pf_cluster_node_index -lt 0 ]] ); do
      echo 'Invalid index (Range: 0-65535 or unset)'
      get_node_index
    done
    ;;
  '')
    echo "If no value is set for the node index, the system assigns a default index derived from the last two octets of the IP address. We recommend, however, that you assign static indices."
    read -e -p "Do you want to assign a default index? (y/n): " -i "y" default_index
    if [[ $default_index =~ ^[Nn] ]]; then
      get_node_index
    fi
    ;;
  *)
     echo 'Invalid index (Range: 0-65535 or unset)'
     get_node_index
  ;;
esac
}


function make_tmp_dir()
{
if [ ! -d "${TMP_DIR}" ]; then
     mkdir -p "${TMP_DIR}"
fi
}


# param1: prefix of the expected file (i.e. <prefix>-<version>.tar.gz)
function check_for_files()
{
local prefix=$1
if [ -f "./${prefix}-${PFVERSION}.tar.gz" ]; then
  cp ./${prefix}-${PFVERSION}.tar.gz "${TMP_DIR}"
fi

if [ -f "${TMP_DIR}${prefix}-${PFVERSION}.tar.gz" ]; then
REMOTE_CHECK_SUM=`curl -m 20 -sI ${BASE_DL_URL}${PFVERSION}/${prefix}-${PFVERSION}.tar.gz | grep ETag | awk '{print $2}' | tr -d '"' | tr --delete '[:space:]' 2>/dev/null`
LOCAL_CHECK_SUM=`md5sum "${TMP_DIR}${prefix}-${PFVERSION}.tar.gz" |awk '{print $1}' | tr --delete '[:space:]'`
  if [[ ! -z "$REMOTE_FILE_CHECKSUM" && "$LOCAL_FILE_CHECKSUM" != "$REMOTE_FILE_CHECKSUM" ]]; then
    echo "Removed local file ${TMP_DIR}${prefix}-${PFVERSION}.tar.gz, This file had a different checksum than the remote version."
    rm "${TMP_DIR}${prefix}-${PFVERSION}.tar.gz"
    mv ./${prefix}-${PFVERSION}.tar.gz ./${prefix}-${PFVERSION}-CORRUPT.tar.gz
  fi
fi

}


function download_upgrade_util()
{
if [ ! -f "${TMP_DIR}pf-upgrade-${PFVERSION}.tar.gz" ]; then
  read -e -p "Could not locate pf-upgrade-${PFVERSION}.tar.gz, would you like to download it? (y/n) " -i "y" download
  if [[ $download =~ ^[Yy]$ ]]; then
    echo "# Downloading pf-upgrade-$PFVERSION.tar.gz"
    curl -f -o "${TMP_DIR}pf-upgrade-$PFVERSION.tar.gz" ${BASE_DL_URL}${PFVERSION}/pf-upgrade-${PFVERSION}.tar.gz || echo Download failed. Exiting. Please retry or manually download pf-upgrade-${PFVERSION}.tar.gz and place it in the same directory as the pf-install.sh
    if [ ! -f ${TMP_DIR}pf-upgrade-$PFVERSION.tar.gz ]; then
        exit 1
    fi
  else
    echo "The update can't be completed without downloading the upgrade utility. Please manually download pf-upgrade-${PFVERSION}.tar.gz and place it in the same directory as pf-install.sh"
    exit 1
  fi
fi
}


function download_pf()
{
if [ ! -f "${TMP_DIR}pingfederate-${PFVERSION}.tar.gz" ]; then
  read -e -p "Could not locate pingfederate-${PFVERSION}.tar.gz, would you like to download it? (y/n) " -i "y" download
  if [[ $download =~ ^[Yy]$ ]]; then
    echo "# Downloading pingfederate-$PFVERSION.tar.gz"
    curl -f -o "${TMP_DIR}pingfederate-$PFVERSION.tar.gz" ${BASE_DL_URL}${PFVERSION}/pingfederate-${PFVERSION}.tar.gz || echo Download failed. Exiting. Please retry or manually download pingfederate-${PFVERSION}.tar.gz and place it in the same directory as the pf-install.sh
    if [ ! -f ${TMP_DIR}pingfederate-$PFVERSION.tar.gz ]; then
    exit 1
    fi
  else
    echo "The installation can't be completed without downloading PingFederate. Please manually download pingfederate-${PFVERSION}.tar.gz and place it in the same directory as pf-install.sh"
    exit 1
  fi
fi
}


function change_ownership()
{
    chown -R pingfederate:pingfederate /usr/local/pingfederate*
}


function addChosenPort()
{
  if [[ ! -x "${1}" ]]; then
    used_addr=${1}:${2}
  else
    used_addr="0.0.0.0:${2}"
  fi

  CHOSEN_PORTS+=(${used_addr})
}


function isPortAlreadyChosen()
{
  if [[ ! -x "${1}" ]]; then
    query_addr=${1}:${2}
  else
    query_addr="0.0.0.0:${2}"
  fi

  for addr in "${CHOSEN_PORTS[@]}" ;
  do :
    if [ "$addr" = "$query_addr" ]; then
      return 0 # found a match
    fi
  done

  return 1 # no match found
}

function copy_java_home_from_temp_location()
{
    if [ -f ${TMP_DIR}/PF_JAVA_HOME.tmp ]; then
        echo "export JAVA_HOME=$JAVA_HOME" > /home/pingfederate/PF_JAVA_HOME
        echo "export PATH=\$PATH:\$JAVA_HOME/bin" >> /home/pingfederate/PF_JAVA_HOME
        chown pingfederate:pingfederate /home/pingfederate/PF_JAVA_HOME
        rm ${TMP_DIR}/PF_JAVA_HOME.tmp
    fi
}


function clean_install() {

make_tmp_dir

check_free_space "/usr/local" "${TMP_DIR}"

check_for_files "pingfederate"
echo " "
download_pf

mode_selection

if [[ $pfmode = CLUSTERED_CONSOLE || $pfmode = CLUSTERED_ENGINE ]]; then
    echo " "
    pf_cluster_bind_address_help="Defines the IP address of the network interface to which the group communication should bind. For machines with more than one network interface, you can use this property to increase performance (particularly with UDP) as well as improve security by segmenting group-communication traffic onto a private network or VLAN. If left blank, one of the available non-loopback IP addresses will be used."
    echo "Enter the IP address where any cluster communication should bind. If left blank, one of the available non-loopback IP addresses will be used."
    get_address pf_cluster_bind_address ""

    pf_cluster_bind_port_help=${no_help_msg}
    echo " "
    echo "Enter the port for the binding address above"
    if [ -n "$pf_cluster_bind_address" ]; then
        get_port_no_neg1 pf_cluster_bind_port 7600 ${pf_cluster_bind_address}
        addChosenPort ${pf_cluster_bind_address} ${pf_cluster_bind_port}
    else
        get_port_no_neg1 pf_cluster_bind_port 7600 "0.0.0.0"
        addChosenPort "0.0.0.0" ${pf_cluster_bind_port}
    fi

    pf_cluster_failure_detection_bind_port_help="Indicates the bind port of a server socket that is opened on the given node and used by other nodes as part of one of the cluster’s failure-detection mechanisms. If zero or unspecified, a random available port is used."
    echo " "
    echo "Enter the port that will be used in case of cluster failure."
    if [ -n "$pf_cluster_bind_address" ]; then
        get_port_and_zero pf_cluster_failure_detection_bind_port 7700 ${pf_cluster_bind_address}
        addChosenPort ${pf_cluster_bind_address} ${pf_cluster_failure_detection_bind_port}
    else
        get_port_and_zero pf_cluster_failure_detection_bind_port 7700 "0.0.0.0"
        addChosenPort "0.0.0.0" ${pf_cluster_failure_detection_bind_port}
    fi

    pf_cluster_node_index_help="Each server in a cluster must have a unique index number, which is used to identify peers and optimize inter-node communication. (Range: 0-65535)"
    get_node_index

    echo " "
    echo "Important: The following settings need to be the same for all nodes in the cluster."
    read -e -p "Do you want inter-node traffic to be encrypted? (y/n): " -i "n" pf_cluster_encrypt
    if [[ $pf_cluster_encrypt =~ ^[Yy]$ ]]; then
        pf_cluster_encrypt="true"
        pf_cluster_auth_pwd2="nullset"
        cluster_auth_pwd_set=false
        while [[ "$cluster_auth_pwd_set" != true ]]; do
            echo "Set the key that will be used for all nodes in the cluster and any nodes joining the cluster. A strong, randomly-generated key (22 or more alphanumerics) is recommended."
            read -e -s -p "Enter the key:  " -i "" pf_cluster_auth_pwd
            echo " "
            read -e -s -p "Confirm key:  " -i "" pf_cluster_auth_pwd2
            echo " "
            if [[ "$pf_cluster_auth_pwd" != "$pf_cluster_auth_pwd2" ]]; then
            echo "Keys do not match"
            elif [[ -z "$pf_cluster_auth_pwd" ]]; then
            echo "Key cannot be empty"
            else
            cluster_auth_pwd_set=true
            fi
        done
    else
        pf_cluster_encrypt="false"
    fi

    echo " "
    echo "Enter the initial hosts to be contacted for joining the cluster. Enter the IP and port for each host, separated by commas."
    pf_cluster_tcp_discovery_initial_hosts_help="Designates the initial hosts to be contacted for group membership information when discovering and joining the group. The value is a comma-separated list of host names (or IPs) and ports. Example: host1[7600],10.0.1.4[7600],host7[1033],10.0.9.45[2231]

    Discovering and managing group membership is more difficult using TCP, which does not provide the built-in group semantics of IP multicast. Therefore, at least one of the members of the group must be known in advance and statically configured on each node. It is recommended that as many hosts as possible be included for this property on each cluster node, to increase the likelihood of new members finding and joining the group.

    For dynamic clusters using TCP as the transport protocol, alternate discovery mechanisms are available. See server/default/conf/tcp.xml for further details. If a dynamic discovery mechanism is used, this property is ignored."
    get_hosts pf_cluster_tcp_discovery_initial_hosts ""

fi

if [[ $pfmode = CLUSTERED_CONSOLE || $pfmode = STANDALONE ]]; then
    echo " "
    pf_console_bind_address_help='This property defines the IP address over which the PingFederate administrative console communicates. Use for deployments where multiple network interfaces are installed on the machine running PingFederate.'
    echo "Enter the IP address where the console communication should bind."
    get_address_and_0000 pf_console_bind_address "0.0.0.0"
fi

if [[ $pfmode = STANDALONE || $pfmode = CLUSTERED_CONSOLE ]]; then
    echo " "
    pf_admin_https_port_help="This property defines the port on which the PingFederate administrative console and API run."
    echo "Enter the port where the PingFederate admin console and API will run."
    get_port pf_admin_https_port 9999 ${pf_console_bind_address}
    addChosenPort ${pf_console_bind_address} ${pf_admin_https_port}
fi

if [[ $pfmode = STANDALONE || $pfmode = CLUSTERED_ENGINE ]]; then

    pf_http_port="-1"

    pf_https_port_help=${no_help_msg}

    echo " "

    echo "Enter the port where PingFederate will listen for encrypted HTTPS (SSL/TLS) traffic."
    get_port pf_https_port 9031 "0.0.0.0"
    addChosenPort "0.0.0.0" ${pf_https_port}

    pf_secondary_https_port="-1"
    enable_help='This property defines a secondary HTTPS port that can be used, for example, with SOAP or artifact SAML bindings or for WS-Trust STS calls. To use this port, change the placeholder value to the port number you want to use.

    Important: If you are using mutual SSL/TLS for either WS-Trust STS authentication or for SAML back-channel authentication, you must use this port for security reasons (or use a similarly configured new listener, with either "WantClientAuth" or "NeedClientAuth" set to "true".'
    echo " "
    read -e -p "Do you want to enable a secondary HTTPS port for additional security measures? (y/n/?) " -i "n" enable
      while [[ $enable = *\?* || $enable = *help* ]]; do
        help=enable_help
        echo " "
        echo "${!help}"
        echo " "
        read -e -p "Do you want to enable a secondary HTTPS port for additional security measures? (y/n/?) " -i "n" enable
      done
      if [[ $enable = y ]]; then
          pf_secondary_https_port_help='This property defines a secondary HTTPS port that can be used, for example, with SOAP or artifact SAML bindings or for WS-Trust STS calls. To use this port, change the placeholder value to the port number you want to use.

          Important: If you are using mutual SSL/TLS for either WS-Trust STS authentication or for SAML back-channel authentication, you must use this port for security reasons (or use a similarly configured new listener, with either "WantClientAuth" or "NeedClientAuth" set to "true".

          '
          get_port pf_secondary_https_port 8888 "0.0.0.0"
          addChosenPort "0.0.0.0" ${pf_secondary_https_port}
      fi
fi

COUNTER=1
while [  $COUNTER -lt 100 ]; do
  if [ ! -d "/usr/local/pingfederate-$COUNTER" ]; then
      tar -mxf ${TMP_DIR}pingfederate-$PFVERSION.tar.gz -C /usr/local/
      mv /usr/local/pingfederate-$PFVERSION /usr/local/pingfederate$COUNTER-$PFVERSION
      break
  fi

  read -e -p "/usr/local/pingfederate-$COUNTER already exists, would you like to create another instance? (y/n) " -i "y" instance
    if [[ $instance =~ ^[Nn]$ ]]; then
        read -e -p "You are about to overwrite the contents in /usr/local/pingfederate-$COUNTER, are you sure? (y/n) " -i "y" overwrite
        if [[ $overwrite =~ ^[Yy]$ ]]; then
            echo " "
            /etc/init.d/pingfederate-$COUNTER stop > /dev/null 2>&1
            rm -rf /usr/local/pingfederate$COUNTER-$PFVERSION
            rm /usr/local/pingfederate-$COUNTER
            tar -mxf ${TMP_DIR}pingfederate-$PFVERSION.tar.gz -C /usr/local/
            mv /usr/local/pingfederate-$PFVERSION /usr/local/pingfederate$COUNTER-$PFVERSION
            break
        else
            echo Mismatched selections please try the installation again, exiting.
            exit 1
        fi
    fi
  let COUNTER=COUNTER+1
done


if [ ! -d "/usr/local/pingfederate-$COUNTER" ]; then
ln -s /usr/local/pingfederate$COUNTER-$PFVERSION/pingfederate /usr/local/pingfederate-$COUNTER
fi

change_ownership

# Adjust settings
check_for_pf_java_home=`cat /home/pingfederate/.bash_profile 2>/dev/null|grep PF_JAVA_HOME`
if [ -z "$check_for_pf_java_home" ];then
echo ". /home/pingfederate/PF_JAVA_HOME" >> /home/pingfederate/.bash_profile
fi

check_for_pf_java_home=`cat /home/pingfederate/.profile 2>/dev/null|grep PF_JAVA_HOME`
if [ -z "$check_for_pf_java_home" ];then
echo ". /home/pingfederate/PF_JAVA_HOME" >> /home/pingfederate/.profile
fi

if [ ! -f "/home/pingfederate/PF_JAVA_HOME" ]; then
echo "export JAVA_HOME=$JAVA_HOME" >> /home/pingfederate/PF_JAVA_HOME
echo "export PATH=\$PATH:$JAVA_HOME/bin" >> /home/pingfederate/PF_JAVA_HOME
chown pingfederate:pingfederate /home/pingfederate/PF_JAVA_HOME
fi

if [[ $pfmode = STANDALONE || $pfmode = CLUSTERED_CONSOLE ]]; then
sed -i "s/pf.admin.https.port=.*$/pf.admin.https.port=$pf_admin_https_port/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
sed -i "s/pf.console.bind.address=.*$/pf.console.bind.address=$pf_console_bind_address/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
fi

if [[ $pfmode = STANDALONE || $pfmode = CLUSTERED_ENGINE ]]; then
sed -i "s/pf.http.port=.*$/pf.http.port=$pf_http_port/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
sed -i "s/pf.https.port=.*$/pf.https.port=$pf_https_port/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
sed -i "s/pf.secondary.https.port=.*$/pf.secondary.https.port=$pf_secondary_https_port/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
fi

if [[ $pfmode = CLUSTERED_CONSOLE || $pfmode = CLUSTERED_ENGINE ]]; then
    if [ -n "${pf_cluster_bind_address}" ]; then
        sed -i "s/pf.cluster.bind.address=.*$/pf.cluster.bind.address=$pf_cluster_bind_address/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
    fi
    sed -i "s/pf.cluster.node.index=.*$/pf.cluster.node.index=$pf_cluster_node_index/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
    sed -i "s/pf.cluster.bind.port=.*$/pf.cluster.bind.port=$pf_cluster_bind_port/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
    sed -i "s/pf.cluster.failure.detection.bind.port=.*$/pf.cluster.failure.detection.bind.port=$pf_cluster_failure_detection_bind_port/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
    sed -i "s/pf.cluster.tcp.discovery.initial.hosts=.*$/pf.cluster.tcp.discovery.initial.hosts=$pf_cluster_tcp_discovery_initial_hosts/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
    sed -i "s/pf.cluster.encrypt=.*$/pf.cluster.encrypt=$pf_cluster_encrypt/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
fi

if [[ $pf_cluster_encrypt = true ]]; then
pf_cluster_auth_pwd=`su -c "export JAVA_HOME=$JAVA_HOME;/usr/local/pingfederate-$COUNTER/bin/obfuscate.sh -l $pf_cluster_auth_pwd" pingfederate`
pf_cluster_auth_pwd=`echo "$pf_cluster_auth_pwd" | sed -e 's/\\//\\\\\\//g'`  # Escape any slashes so that sed doesn't try to interpret them as delimiters
pf_cluster_auth_pwd=${pf_cluster_auth_pwd#$'\n'}
sed -i "s/pf.cluster.auth.pwd=.*$/pf.cluster.auth.pwd=$pf_cluster_auth_pwd/g" /usr/local/pingfederate-$COUNTER/bin/run.properties
fi

# Set operational mode
sed -i "s/pf.operational.mode=.*$/pf.operational.mode=$pfmode/g" /usr/local/pingfederate-$COUNTER/bin/run.properties

# Optimize JVM heap settings
# Always generate jvm-memory.options for new installs if memoryoptions.sh script exists (post 9.1) and do not run it for older versions
[ -f "/usr/local/pingfederate-$COUNTER/bin/memoryoptions.sh" ]
run_script=$?
run_memory_options_if_necessary /usr/local/pingfederate-$COUNTER/ $run_script

copy_java_home_from_temp_location

# install as service
service_tool "/usr/local/pingfederate-${COUNTER}/tools" install \
                                                    -name pingfederate-${COUNTER} \
                                                    -home /usr/local/pingfederate-${COUNTER} \
                                                    -start "yes" \
                                                    -log pf-service-install.log \
                                                    -backup pf-service-backup \
|| die "The service installation was not successful. See 'pf-service-install.log' for details."

show_final_message=true

if grep -q "Service installation skipped." "${TMP_DIR}/${SERVICE_OUTPUT}"; then
    show_final_message=false
fi

if [[ "$show_final_message" = true ]]; then
  if [[ $pfmode = CLUSTERED_CONSOLE || $pfmode = STANDALONE ]]; then
    echo " "
    echo "Please open your browser to https://<yourhost>:$pf_admin_https_port/pingfederate/app to finalize your setup."
    echo " "
  fi
fi

exit 0

}

function get_installs()
{
INSTALLCOUNTER=1
i=0
while [  $INSTALLCOUNTER -lt 100 ]; do
  if [ -d "/usr/local/pingfederate-$INSTALLCOUNTER" ]; then
    PFINSTALLS[i]="/usr/local/pingfederate-$INSTALLCOUNTER"
    let i=i+1
  fi
  let INSTALLCOUNTER=INSTALLCOUNTER+1
done
}

# Param1: path to the pf install.
function get_version()
{
    prereq unzip
    VERSION="Unknown"
    if [ -e "${1}/bin/pf-startup.jar" ]; then
        VERSION=`unzip -q -c "${1}/bin/pf-startup.jar" META-INF/maven/pingfederate/pf-startup/pom.properties | grep 'version' | cut -d '=' -f 2`
    fi
}

# Param1: path to the pf install.
function get_node_type()
{
    NODE_TYPE="Unknown"
    if [ -e "${1}/bin/run.properties" ]; then
        NODE_TYPE=`cat ${1}/bin/run.properties | grep 'pf.operational.mode=' | cut -d '=' -f 2 | tr -d '[[:space:]]'`
    fi
}

# Param1: version to see if it is greater than param2
# Param2: version to compare to.
function is_ver_greater_than() {
    [ "$1" = "$2" ] && return 1 || [  "$2" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

#Param1: destination PF upgraded folder
#Param2: condition to run the script depending on if upgrade or new install
function run_memory_options_if_necessary() {
    if (( $2 == 0 ));
    then
        $1bin/memoryoptions.sh
        change_ownership $1conf
    fi
}

function get_upgradeable_instances()
{
get_installs
local count=0
for i in "${PFINSTALLS[@]}"
do
   :
   VERSION=""
   get_version $i
   if is_ver_greater_than $PFVERSION $VERSION; then
      ELIGIBLE_UPGRADES[$count]=$i
      ELIGIBLE_UPGRADES_VER[$count]=$VERSION
      let count=count+1
   fi
done
}

function choose_instance_to_upgrade()
{
echo "Here is the list of PingFederate instances on this machine:"
local count=1
for i in "${ELIGIBLE_UPGRADES[@]}"
do
   :
   ver=${ELIGIBLE_UPGRADES_VER[$(expr $count-1)]}
   get_node_type $i
   echo -e "\t${count}. ${i} (Version: ${ver}, Type: ${NODE_TYPE})"
   let count=count+1
done

local num_instances=${#ELIGIBLE_UPGRADES[@]}

read -e -p "Please choose which instance you would like to update (1-${num_instances}): "  INSTANCE_TO_UPGRADE

if [ "$INSTANCE_TO_UPGRADE" -lt 1 -o "$INSTANCE_TO_UPGRADE" -gt "$num_instances" ]; then
    echo "Invalid instance number (Range: 1-${num_instances})"
    choose_instance_to_upgrade
fi

UPGRADE_INSTANCE=${ELIGIBLE_UPGRADES[$(expr $INSTANCE_TO_UPGRADE-1)]}
}

# param1 - Path that the service would be pointing to.
function find_service()
{
    SERVICE_PATH=`grep -l "${1}" /etc/init.d/*`
}

function get_pf_path()
{
    read -e -p "Enter the path to the PingFederate instance that should be upgraded: " pf_path
    if [ ! -d "$pf_path" ]; then
        echo "'${pf_path}' does not exist, please enter the correct path to PingFederate."
        get_pf_path
    fi

    get_proper_pf_path "$pf_path"

    if [[ $? -eq 1 ]]; then
        get_pf_path
        return
    fi

    correct_path="${PROPER_PATH}"

    get_version "$correct_path"

    if [ "$VERSION" = "Unknown" ]; then
        echo "'${correct_path}' does not look to contain a valid PingFederate instance."
        get_pf_path
    fi

    is_ver_greater_than $PFVERSION $VERSION
    if [[ $? -eq 1 ]]; then
        echo "This instance of PingFederate (Version: ${VERSION}) is the same or greater version than ${PFVERSION} and does not need to be upgraded."
        exit 1
    fi

    TARGET_UPGRADE=${correct_path}
}


function get_proper_pf_path()
{
    local folder=$1
    local num_pf_instances=`find "${folder}" -type f -follow -print | grep -F 'bin/run.properties' | wc -l`

    if [[ ${num_pf_instances} -ne "1" ]]; then
        if [[ ${num_pf_instances} -eq "0" ]]; then
            echo "There are no valid PingFederate instances found under the directory '${folder}'. Please provide the path to your PingFederate instance."
        else
            echo "There were multiple PingFederate instances found under the directory '${folder}'. Please provide a path directly to the PingFederate you wish to upgrade."
        fi
        return 1
    fi

    local path=`find "${folder}" -type f -follow -print | grep -F 'bin/run.properties' | tr -d '\n'`
    if [ -z "${path}" ]; then
        echo "Could not find a run.properties file under ${folder}. Please provide the path to the PingFederate that you wish to upgrade."
        return 1
    fi

    PROPER_PATH=${path/bin\/run.properties/}
}

function restart_pf_and_exit()
{
    echo " "
    if [ -n "${SERVICE_PATH}" ]; then
        echo "Starting up existing PingFederate.."
        ${SERVICE_PATH} start
    fi
    exit 1
}

# param1 - Folder to get free space for
# Sets $FREE_SPACE to the amount of free space for that folder (in megabytes)
function get_free_space_for()
{
    FREE_SPACE=$(($(stat -f --format="%a*%S" "$1")/1024/1024))
}

# param1 - Location where PF will be placed
# param2 - Temp folder where archives are stored and exploded.
function check_free_space()
{
    get_free_space_for $1
    if [[ $FREE_SPACE -lt $PF_SIZE_REQ ]]; then
        echo "The installation process requires ${PF_SIZE_REQ}MB but finds only ${FREE_SPACE}MB available in '$1'. Please free up space to continue."
        exit 1
    fi

    get_free_space_for $2
    if [[ $FREE_SPACE -lt $PF_TMP_SIZE_REQ ]]; then
        echo "The installation process requires ${PF_TMP_SIZE_REQ}MB to be free in the temporary directory but finds only ${FREE_SPACE}MB available in '$2'. Please free up space to continue."
        exit 1
    fi
}

function upgrade()
{
declare -a PFINSTALLS
declare -a ELIGIBLE_UPGRADES
declare -a ELIGIBLE_UPGRADES_VER

PF_TMP_SIZE_REQ=$((PF_TMP_SIZE_REQ + 325)) # Add 50MB for pf-upgrade.tar.gz, 200MB uncompressed PF folder, 75MB uncompressed pf-upgrade folder.

# User specified folder to upgrade.
if [ -n "$UPGRADE_FOLDER" ]; then
    if [ ! -d "$UPGRADE_FOLDER" ]; then
        echo "'${UPGRADE_FOLDER}' does not exist, please enter the correct path to PingFederate."
        get_pf_path
    fi

    get_proper_pf_path "$UPGRADE_FOLDER"
    if [[ $? -eq 1 ]]; then
        exit 1
    fi

    UPGRADE_FOLDER="${PROPER_PATH}"
    get_version "${UPGRADE_FOLDER}"
    is_ver_greater_than $PFVERSION $VERSION
    if [[ $? -eq 1 ]]; then
        echo "This instance of PingFederate (Version: ${VERSION}) is the same or greater version than ${PFVERSION} and does not need to be upgraded."
        exit 1
    fi

    UPGRADE_INSTANCE=${UPGRADE_FOLDER}
    NEW_PF_FOLDER=${OUTPUT_FOLDER}
    # Add slash if needed.
    if [[ "${NEW_PF_FOLDER}" != */ ]]; then
        NEW_PF_FOLDER=$NEW_PF_FOLDER"/"
    fi

    find_service "${UPGRADE_INSTANCE}" # sets SERVICE_PATH
    TARGET_UPGRADE=${UPGRADE_INSTANCE}
else
    get_upgradeable_instances

    if [ ${#ELIGIBLE_UPGRADES[@]} -eq 0 ]; then
        echo "No instances of PingFederate on this machine were found that need to be upgraded."
        exit 1
    elif [ ${#ELIGIBLE_UPGRADES[@]} -eq 1 ]; then
        UPGRADE_INSTANCE=${ELIGIBLE_UPGRADES[0]}
        get_version ${UPGRADE_INSTANCE}
        get_node_type ${UPGRADE_INSTANCE}
        echo "Found one instance that can be upgraded at ${UPGRADE_INSTANCE} (Version: ${VERSION}, Type: ${NODE_TYPE})"
        read -e -p "Would you like to upgrade this instance? (y/n) " -i "y" confirm_upgrade
        if [[ $confirm_upgrade =~ ^[Nn]$ ]]; then
          exit 1
        fi
    else
        choose_instance_to_upgrade
    fi
    NEW_PF_FOLDER=${UPGRADE_INSTANCE/-/}-${PFVERSION}/
    SERVICE_PATH=/etc/init.d/${UPGRADE_INSTANCE/\/usr\/local\//}
    TARGET_UPGRADE=`readlink -f ${UPGRADE_INSTANCE}`

    echo " "
    echo "The PingFederate instance located at '$TARGET_UPGRADE' is about to be upgraded."
    read -e -p "Is this the correct path to upgrade? (y/n) " -i "y" continue
    if [[ $continue =~ ^[Nn]$ ]]; then
      get_pf_path
    fi
fi

if [ -d ${NEW_PF_FOLDER} ]; then
    read -e -p "${NEW_PF_FOLDER} folder already exists, would you like to overwrite this folder? (y/n) " -i "y" instance
    if [[ $instance =~ ^[Yy]$ ]]; then
        read -e -p "You are about to overwrite the contents in ${NEW_PF_FOLDER}, are you sure? (y/n) " -i "y" overwrite
        if [[ $overwrite =~ ^[Yy]$ ]]; then
            echo " "
            rm -rf "${NEW_PF_FOLDER}"
        else
            echo Please specify a different path and try again, exiting.
            exit 1
        fi
    else
        echo Please specify a different path and try again, exiting.
        exit 1
    fi
fi

mkdir -p "${NEW_PF_FOLDER}"
make_tmp_dir
check_free_space "${NEW_PF_FOLDER}" "${TMP_DIR}"

check_for_files "pf-upgrade"
check_for_files "pingfederate"

echo " "

download_upgrade_util
download_pf

# Extract the service-installer tool
tar -xf ${TMP_DIR}pingfederate-$PFVERSION.tar.gz -C ${TMP_DIR} --strip-components=3 --wildcards "*/service-installer.jar"

local instance_name_in_use=${UPGRADE_INSTANCE/\/usr\/local\//}
service_tool "${TMP_DIR}" stop -name ${instance_name_in_use} -multiple true
service_stop_result=$?

tar -mxf "${TMP_DIR}pf-upgrade-$PFVERSION.tar.gz" -C "${TMP_DIR}"

echo "Upgrading PingFederate to ${PFVERSION}.."
echo " "

set -o pipefail # sets status to failure if ANY command in pipes fail.
"${TMP_DIR}pf-upgrade-$PFVERSION/bin/upgrade.sh" "${TARGET_UPGRADE}" "${TMP_DIR}" "${TMP_DIR}pingfederate-${PFVERSION}.tar.gz" ${CUSTOM_UPGRADE} 2>&1 | tee "${TMP_DIR}upgrade-full.log"

if [ $? -ne 0 ]; then
    echo " "
    echo "The upgrade was not successful, please view the full log at ${TMP_DIR}upgrade-full.log for more info. Exiting.."
    restart_pf_and_exit
fi

# If the upgrade log doesnt exist, or is empty, then upgrade probably failed even though the exit code is zero.
if [ ! -s "${TMP_DIR}pf-upgrade-$PFVERSION/log/upgrade.log" ]; then
    echo " "
    echo "The upgrade process exited early, please view the full log at ${TMP_DIR}upgrade-full.log for more info. Exiting.."
    restart_pf_and_exit
fi

rm -rf "${NEW_PF_FOLDER}"
mv "${TMP_DIR}pingfederate-${PFVERSION}" "${NEW_PF_FOLDER}"
mv "${TMP_DIR}upgrade-full.log" "${NEW_PF_FOLDER}"

get_user_group "${TARGET_UPGRADE}" # Sets USER_GROUP
chown -R ${USER_GROUP} "${NEW_PF_FOLDER}"

local errors=$(sed -ne "s/.*with \([0-9]\+\) error.*/\1/p" "${NEW_PF_FOLDER}upgrade-full.log")
local warnings=$(sed -ne "s/.*and \([0-9]\+\) warning.*/\1/p" "${NEW_PF_FOLDER}upgrade-full.log")

echo " "
if [ $errors -gt 0 -o $warnings -gt 0 ]; then
    read -e -p "There were ${errors} error(s) and ${warnings} warning(s) encountered during the upgrade. Would you like to continue upgrading to ${PFVERSION}? (y/n) " -i "y" continue
    if [[ $continue =~ ^[Nn]$ ]]; then
        restart_pf_and_exit
    fi
fi

# Only create symlink if they did not specify the folder.
if [ -z "$UPGRADE_FOLDER" ]; then
    ln -snf "${NEW_PF_FOLDER}pingfederate" "${UPGRADE_INSTANCE}"
fi

copy_java_home_from_temp_location

#UPGRADE_FOLDER="${PROPER_PATH}"
#if jvm-memory.options file does not exist in source folder, we will generate it after upgrade
#[ ! -f "$UPGRADE_FOLDER/pingfederate/bin/jvm-memory.options" ]
#run_script=$?
#run_memory_options_if_necessary "${NEW_PF_FOLDER}pingfederate/" $run_script

# Install new service, which will prompt to backup and replace the existing service
service_tool "${UPGRADE_INSTANCE}/tools" install \
                                -name ${instance_name_in_use} \
                                -home "${UPGRADE_INSTANCE}" \
                                -start yes \
                                -log pf-service-install.log \
                                -backup pf-service-backup
service_install_result=$?
# Update symbolic link AFTER removing the old service
if [ ${service_install_result} -eq 0 ]; then
    echo " "
    echo "PingFederate started..."
else
    echo " "
    echo "Please stop the current PingFederate instance and start up version ${PFVERSION} with ${NEW_PF_FOLDER}pingfederate/bin/run.sh"
fi

change_ownership

echo " "
echo "Please review documentation on post-upgrade tasks."
echo "PingFederate was successfully upgraded to ${PFVERSION}!"
}

# param1 - Path to get ownership info for.
function get_user_group()
{
    USER_GROUP=`stat -c '%U:%G' "${1}"`
}

function print_usage()
{
echo "Usage: pf-install-${PFVERSION}.sh [-u] [-c] [-f <path>] [-o <path>] [-t <path>] [-h]
    -u  Indicate that you would like to upgrade PingFederate on this machine.
    -c  Used with -u to run the upgrade in custom mode.
    -f  Used with -u to indicate the path to PingFederate that should be upgraded.
    -o  Used with -f to specify the path where the upgraded PingFederate should be located.
    -t  Specify a temporary directory for this script to use. (Default: /tmp/ping-tmp/)
    -h  Print this usage message and exit.
"
}

########################################################################################################################
#                                                                                                                      #
#                                                MAIN METHOD                                                           #
#                                                                                                                      #
########################################################################################################################

#


# Require script run as root
if (( $EUID != 0 )); then
    echo "Please run as root or sudo command."
    exit 1
fi

# Get options
while getopts ":hv:b:ucf:o:t:" opt; do
  case $opt in
    b)
      BASE_DL_URL=$OPTARG
      ;;
    t)
      TMP_DIR=$OPTARG
      if [[ "${TMP_DIR}" != */ ]]; then
        TMP_DIR=$TMP_DIR"/"
      fi
      ;;
    u)
      UPGRADE=1
      ;;
    c)
      CUSTOM_UPGRADE="-c"
      ;;
    f)
      UPGRADE_FOLDER=$OPTARG
      ;;
    o)
      OUTPUT_FOLDER=$OPTARG
      ;;
    h)
      print_usage
      exit 0
      ;;
    ?)
      print_usage
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      print_usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

if [[ -n "$UPGRADE_FOLDER" && -z "$OUTPUT_FOLDER" ]]; then
  echo "Missing arguments: -o is required when using the '-f' flag"
  print_usage
  exit 1
fi

if [[ -n "$OUTPUT_FOLDER" && -z "$UPGRADE_FOLDER" ]]; then
    echo "Invalid Arguments: -o is only allowed when specifying the folder to upgrade (-f)"
    print_usage
    exit 1
fi

if [[ -n "$UPGRADE_FOLDER" && ! $UPGRADE ]]; then
    echo "Invalid Arguments: -f is only allowed when upgrading (-u)"
    print_usage
    exit 1
fi

if [[ -n "$OUTPUT_FOLDER" && ! $UPGRADE ]]; then
    echo "Invalid Arguments: -o is only allowed when upgrading (-u)"
    print_usage
    exit 1
fi

if [[ -n "$CUSTOM_UPGRADE" && ! $UPGRADE ]]; then
    echo "Invalid Arguments: -c is only allowed when upgrading (-u)"
    print_usage
    exit 1
fi

if [[ $TMP_DIR = *[[:space:]]* ]]; then
    echo "Invalid Arguments: The temporary directory path (-t) is not allowed to contain spaces."
    print_usage
    exit 1
fi

prereq tar
prereq sed
prereq curl
prereq awk
prereq nc


echo '
    ____  _                ____    __           __  _ __
   / __ \(_)___  ____ _   /  _/___/ /__  ____  / /_(_) /___  __
  / /_/ / / __ \/ __ `/   / // __  / _ \/ __ \/ __/ / __/ / / /
 / ____/ / / / / /_/ /  _/ // /_/ /  __/ / / / /_/ / /_/ /_/ /
/_/   /_/_/ /_/\__. /  /___/\__._/\___/_/ /_/\__/_/\__/\__. /
              /____/                                  /____/
'
echo "PingFederate ${PFVERSION} Installation Script"
echo " "
echo 'Welcome to PingFederate. Follow these step-by-step instructions to complete your installation.'
echo 'Some steps have more information available, which you can access by typing "?" or "help"'
echo " "

# Detect Operating System Distro
OS=`lowercase \`uname\``
KERNEL=`uname -r`
MACH=`uname -m`

if [ "{$OS}" == "windowsnt" ]; then
    OS=windows
elif [ "{$OS}" == "darwin" ]; then
    OS=mac
else
    OS=`uname`
    if [ "${OS}" = "SunOS" ] ; then
        OS=Solaris
        ARCH=`uname -p`
        OSSTR="${OS} ${REV}(${ARCH} `uname -v`)"
    elif [ "${OS}" = "AIX" ] ; then
        OSSTR="${OS} `oslevel` (`oslevel -r`)"
    elif [ "${OS}" = "Linux" ] ; then
        if [ -f /etc/redhat-release ] ; then
            DistroBasedOn='RedHat'
            DIST=`cat /etc/redhat-release |sed s/\ release.*//`
            PSUEDONAME=`cat /etc/redhat-release | sed s/.*\(// | sed s/\)//`
            REV=`cat /etc/redhat-release | sed s/.*release\ // | sed s/\ .*//`
        elif [ -f /etc/SuSE-release ] ; then
            DistroBasedOn='SuSe'
            PSUEDONAME=`cat /etc/SuSE-release | tr "\n" ' '| sed s/VERSION.*//`
            REV=`cat /etc/SuSE-release | tr "\n" ' ' | sed s/.*=\ //`
        elif [ -f /etc/mandrake-release ] ; then
            DistroBasedOn='Mandrake'
            PSUEDONAME=`cat /etc/mandrake-release | sed s/.*\(// | sed s/\)//`
            REV=`cat /etc/mandrake-release | sed s/.*release\ // | sed s/\ .*//`
        elif [ -f /etc/debian_version ] ; then
            DistroBasedOn='Debian'
            DIST=`cat /etc/lsb-release | grep '^DISTRIB_ID' | awk -F=  '{ print $2 }'`
            PSUEDONAME=`cat /etc/lsb-release | grep '^DISTRIB_CODENAME' | awk -F=  '{ print $2 }'`
            REV=`cat /etc/lsb-release | grep '^DISTRIB_RELEASE' | awk -F=  '{ print $2 }'`
        fi
        if [ -f /etc/UnitedLinux-release ] ; then
            DIST="${DIST}[`cat /etc/UnitedLinux-release | tr "\n" ' ' | sed s/VERSION.*//`]"
        fi
        OS=`lowercase $OS`
        DistroBasedOn=`lowercase $DistroBasedOn`
        readonly OS
        readonly DIST
        readonly DistroBasedOn
        readonly PSUEDONAME
        readonly REV
        readonly KERNEL
        readonly MACH
    fi

fi


if [[ "${DistroBasedOn}" != "redhat" && "${DistroBasedOn}" != "debian" ]]; then
echo This script is only supported on Redhat.
exit 1
fi

if [ "${DistroBasedOn}" == "debian" ]; then
  echo You are running an unsupported distro based off Debian.
  read -e -p "Would you like to continue anyways (y/n) " -i "n" confirm_install
    if [[ $confirm_install =~ ^[Nn]$ ]]; then
      exit 1
    fi
fi

LOCAL_USER_JAVA_HOME=$JAVA_HOME

# If PF_JAVA_HOME exists source it
if [ -f /home/pingfederate/PF_JAVA_HOME ]; then
   . /home/pingfederate/PF_JAVA_HOME
fi

ORIGINAL_PF_JAVA_HOME=$JAVA_HOME

# Compare the two versions. Strip the path, and compare the versions only.
if [ "${LOCAL_USER_JAVA_HOME}" != "${ORIGINAL_PF_JAVA_HOME}" ]; then
   echo "Local user's JAVA_HOME version: $LOCAL_USER_JAVA_HOME"
   echo "Pingfederate JAVA_HOME version: $ORIGINAL_PF_JAVA_HOME"
   read -e -p "The two versions are different, do you want to update the PingFederate version to match the local Java version? (y/n) " -i "y" confirmation
   if [[ $confirmation =~ ^[Yy]$ ]]; then
        # Write to TMP_DIR/PF_JAVA_HOME.tmp
        make_tmp_dir
        echo "export JAVA_HOME=$LOCAL_USER_JAVA_HOME" > ${TMP_DIR}/PF_JAVA_HOME.tmp
        # Now source the temp file, in order to use the JAVA_HOME going forward
        . ${TMP_DIR}/PF_JAVA_HOME.tmp

        echo "New Pingfederate JAVA_HOME will be set to: $LOCAL_USER_JAVA_HOME if successful."
   fi
fi

# Check for JAVA
if [ -z $JAVA_HOME ]; then
  read -e -p "JAVA_HOME not set, do you want to set it? (y/n) " -i "y" confirmation
    if [[ $confirmation =~ ^[Nn]$ ]]; then
       echo "JAVA_HOME not set, please install Java 8 or 11 and set JAVA_HOME"
       exit 1
    fi
read -e -p "Please set JAVA_HOME: " -i "/opt/jdk" JAVA_HOME
fi

if [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
    echo "Found java executable in JAVA_HOME"
    _java="$JAVA_HOME/bin/java"
else
    echo "No java in PATH or JAVA_HOME, please correct and rerun this script"
    exit 1
fi

JAVA_VERSION_STRING=`"$_java" -version 2>&1 | head -1 | cut -d '"' -f2`
javaSupportedVersion=0
javaIsJava8=0

case "$JAVA_VERSION_STRING" in
    1.8*)            # Java 8
        javaSupportedVersion=1
        javaIsJava8=1
        ;;
    1.*)             # Earlier than Java 8 not supported
        ;;
    9|9.*|10|10.*)   # Pre-LTS Java 9 and 10 not supported
        ;;
    *)               # Java 11 or later
        javaSupportedVersion=1
        ;;
esac

if [[ $javaSupportedVersion == 0 ]]; then
        echo ""
        echo "!! WARNING !!"
        echo "Java version ${JAVA_VERSION_STRING} is not supported for running PingFederate. Please install Java 8 or 11."
        echo ""

        confirm "Do you want to continue with installation?" \
		"Enter 'y' to continue, despite potential problems."
        if [[ ! ${USER_CONFIRMED} ]]; then
       		 die "Installation aborted."
        fi
else
        echo "Version ${JAVA_VERSION_STRING}"
fi

echo " "

# Create pingfederate user
if [ ! -d "/home/pingfederate" ]; then
    useradd -d /home/pingfederate pingfederate
    if [ ! -d "/home/pingfederate" ]; then
        mkdir /home/pingfederate
    fi

    chown -R pingfederate:pingfederate /home/pingfederate
fi

checkSELinux

if [ $UPGRADE ]; then
    prereq unzip
    upgrade
else
    clean_install
fi
