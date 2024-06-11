#!/bin/bash
# Configure iptables firewall

# Limit PATH
PATH="/sbin:/usr/sbin:/bin:/usr/bin"
export UDP_PORT=123,5060,5080,4569,10000:20000
export TCP_PORT=22,80
export WAN=$(ls /sys/class/net | grep -v lo)
LOCALNET=$(ip -o -f inet addr show | awk '/scope global/ {print $4}')

# iptables configuration
firewall_start() {
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -X
    iptables -t nat -X
    iptables -t mangle -X
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -s ${LOCALNET} -j ACCEPT -m comment --comment "Local Network"
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -m state --state NEW -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type destination-unreachable -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type time-exceeded -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
    iptables -A INPUT -p udp --source-port 53 -s 8.8.8.8 -j ACCEPT
    iptables -A INPUT -s 8.8.8.8/32  -p tcp -m tcp --dport 53 -j ACCEPT
    iptables -A INPUT -s 8.8.4.4/32  -p tcp -m tcp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 636:636 -j ACCEPT
    iptables -A INPUT -p tcp --dport 636:636 -j ACCEPT
    iptables -A INPUT -p udp -m udp --dport 636 -j ACCEPT
    iptables -A INPUT -p tcp -m tcp --dport 636 -j ACCEPT
    iptables -A INPUT -p udp --dport 443:443 -j ACCEPT
    iptables -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p udp -m udp --dport 443 -j ACCEPT

    #Drop
    iptables -I INPUT -p udp --dport 5060 -m string --string "friendly-scanner" --algo bm -j DROP
    iptables -I INPUT -p udp --dport 5060 -m string --string "sip-scan" --algo bm -j DROP
    iptables -I INPUT -p udp --dport 5060 -m string --string "sundayddr" --algo bm -j DROP
    iptables -I INPUT -p udp --dport 5060 -m string --string "iWar" --algo bm -j DROP
    iptables -I INPUT -p udp --dport 5060 -m string --string "sipsak" --algo bm -j DROP
    iptables -I INPUT -p udp --dport 5060 -m string --string "sipvicious" --algo bm -j DROP
    iptables -I INPUT -p udp --dport 5060 -m string --string "pplsip" --algo bm -j DROP
    iptables -I INPUT -p udp --dport 5060 -m string --string "Cisco-SIPGateway" --algo bm -j DROP
    iptables -A INPUT -p tcp --dport 0:65535 -j DROP
    iptables -A INPUT -p udp --dport 0:65535 -j DROP

}

# clear iptables configuration
firewall_stop() {
    iptables -F
    iptables -X
    iptables -P INPUT   ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT  ACCEPT
}

# execute action
case "$1" in
  start|restart)
    echo "Starting firewall"
    firewall_stop
    firewall_start
    ;;
  stop)
    echo "Stopping firewall"
    firewall_stop
    ;;
esac
