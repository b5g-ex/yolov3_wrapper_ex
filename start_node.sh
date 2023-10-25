#!/bin/sh

#
# set variables
#
: ${NODE_NAME:="yolov3_wrapper_ex"}
: ${NODE_IPADDR:="127.0.0.1"}
: ${COOKIE:="idkp"}
: ${INET_DIST_LISTEN_MIN:="9100"}
: ${INET_DIST_LISTEN_MAX:="9155"}
: ${MY_PROCESS_NAME:=":yolov3_wrapper_ex"}
: ${MODEL:="608"}
: ${USE_XLA:="false"}

#
# start node
#
echo "exec:
MY_PROCESS_NAME=\"${MY_PROCESS_NAME}\" MODEL=\"${MODEL}\" USE_XLA=\"${USE_XLA}\" iex \
--name \"${NODE_NAME}@${NODE_IPADDR}\" \
--cookie \"${COOKIE}\" \
--erl \"-kernel inet_dist_listen_min ${INET_DIST_LISTEN_MIN} inet_dist_listen_max ${INET_DIST_LISTEN_MAX}\" -S mix
"

MY_PROCESS_NAME="${MY_PROCESS_NAME}" MODEL="${MODEL}" USE_XLA="${USE_XLA}" iex \
  --name "${NODE_NAME}@${NODE_IPADDR}" \
  --cookie "${COOKIE}" \
  --erl "-kernel inet_dist_listen_min ${INET_DIST_LISTEN_MIN} inet_dist_listen_max ${INET_DIST_LISTEN_MAX}" -S mix
