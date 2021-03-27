#!/usr/bin/python3
#
# Copyright (c) 2019-2020 Arm Limited. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#

import os
import sys
import yaml

"""
The whole messages will go into 'lava.log' and if there are 'feedback' level message,
depends on the message namespace 'ns', the corresponding message will go into separated files
            Message                   Separated log file
           level, ns
--------------------------------------------------------
all                                     lava.log
lvl='target'                            lava-uart0.log
lvl='feedback' and no 'ns'              feedback.log
lvl='feedback', ns='terminal_1'         lava-uart1.log
lvl='feedback', ns='terminal_2'         lava-uart2.log
lvl='feedback', ns='terminal_3'         lava-uart3.log
--------------------------------------------------------
"""

USAGE = f"Usage: {sys.argv[0]} /path/to/lava-job-plain-log.log"

separated_log_file = {"all": "lava.log", \
                      "target": "lava-uart0.log", \
                      "feedback-terminal_1": "lava-uart1.log", \
                      "feedback-terminal_2": "lava-uart2.log", \
                      "feedback-terminal_3": "lava-uart3.log", \
                      "feedback": "feedback.log"}
opened_logfile = dict()

if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        raise SystemExit(USAGE)

    plain_log = args[0]
    des_dir = os.path.dirname(plain_log)
    if len(des_dir) == 0:
        des_dir = "."

    if not os.path.exists(plain_log):
        raise SystemExit("The file '{}' is not exist!!".format(plain_log))

    with open(plain_log, "r") as job_log:
        log_list = yaml.load(job_log, Loader=yaml.SafeLoader)
        try:
            full_test_log = "{}/{}".format(des_dir, separated_log_file["all"])
            opened_logfile["all"] = open(full_test_log, "w")
            for line in log_list:
                level = line["lvl"]
                msg = line["msg"]
                dt  = line["dt"]
                if (level == "target") or (level == "feedback"):
                    log_file_id = level
                    if "ns" in line:
                        log_file_id = "{}-{}".format(log_file_id, line["ns"])
                    if log_file_id not in opened_logfile:
                        des_log_file = "{}/{}".format(des_dir, separated_log_file[log_file_id])
                        opened_logfile[log_file_id] = open(des_log_file, "w")
                    try:
                        opened_logfile[log_file_id].write("{}\n".format(msg))
                    except UnicodeEncodeError:
                        msg = (
                            msg
                            .encode("ascii", errors="replace")
                            .decode("ascii")
                        )
                        opened_logfile[log_file_id].write("{}\n".format(msg))
                # log to 'lava.log'
                opened_logfile["all"].write("{} {}\n".format(dt.split(".")[0], msg))
        except IOError as err:
            print("File Error: " + str(err))

        finally:
            for log_file in opened_logfile:
                opened_logfile[log_file].close()
