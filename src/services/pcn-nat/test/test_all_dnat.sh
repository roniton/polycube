#!/usr/bin/env bash

#         TOPOLOGY
#
#                                  +----------+
#         veth1 (10.0.1.1)---------|    r1    |--------- veth2 (10.0.2.1)
#                               ^  +----------+  ^
#                               |                |
#                             to_veth1        to_veth2 (nat)
#

# TEST 12
# test all protocols destination nat

source "${BASH_SOURCE%/*}/helpers.bash"

function test_tcp {
    sudo ip netns exec ns1 netcat -l -w 5 $tcp_port&
	sleep 2
	sudo ip netns exec ns2 netcat -w 2 -nvz $missing_ip $tcp_port
	sleep 4
}

function test_tcp_fail {
    sudo ip netns exec ns1 netcat -l -w 5 $tcp_port&
	sleep 2
	test_fail sudo ip netns exec ns2 netcat -w 2 -nvz $missing_ip $tcp_port
	sleep 4
}

function test_udp {
	npingOutput="$(sudo ip netns exec ns2 nping --udp -c 1 -p $udp_port --source-port 50000 $missing_ip)"
    if [[ $npingOutput != *"Rcvd: 1"* ]]; then
        exit 1
    fi
}

function cleanup {
    set +e
    delete_veth 2
    polycubectl nat del nat1
    polycubectl router del r1
    sudo pkill -SIGTERM netcat
}
trap cleanup EXIT

veth1_ip=10.0.1.1
veth2_ip=10.0.2.1
to_veth2_ip=10.0.2.254
to_veth1_ip=10.0.1.254
missing_ip=10.0.3.1
tcp_port=60123
udp_port=3000

set -x
set -e

create_veth_net 2

polycubectl nat add nat1
polycubectl router add r1

polycubectl router r1 ports add to_veth1 ip=$to_veth1_ip/24 peer=veth1
polycubectl router r1 ports add to_veth2 ip=$to_veth2_ip/24 peer=veth2

polycubectl attach nat1 r1:to_veth2 position=first

test_tcp_fail

test_fail test_udp

test_fail sudo ip netns exec ns2 ping $missing_ip -c 3

# Add rule for the ICMP Destination Unreachable packet that comes back when testing UDP
polycubectl nat1 rule snat append internal-net=$veth1_ip/32 external-ip=$missing_ip

polycubectl nat1 rule dnat append external-ip=$missing_ip internal-ip=$veth1_ip

test_tcp

test_udp

sudo ip netns exec ns2 ping $missing_ip -c 3
