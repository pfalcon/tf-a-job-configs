#!/usr/bin/python3
#
# Copyright (c) 2019-2020 Arm Limited. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#

import os
import sys
import yaml
from shutil import copyfile

"""
The whole messages will go into 'lava.log' and if there are 'feedback' level message,
depends on the message namespace 'ns', the corresponding message will go into separated files
            Message                   Separated log file
           level, ns
--------------------------------------------------------
all                                     lava.log
lvl='target'                            lava-uart0.log
lvl='feedback', ns='terminal_1'         lava-uart1.log
lvl='feedback', ns='terminal_2'         lava-uart2.log
lvl='feedback', ns='terminal_3'         lava-uart3.log
anything else in lvl='feedback'         feedback.log
messages
--------------------------------------------------------
"""

USAGE = f"Usage: {sys.argv[0]} /path/to/lava-job-plain-log.log"

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
        try:
            log_list = yaml.load(job_log, Loader=yaml.SafeLoader)
        except yaml.YAMLError as exc:
            print ("Error while parsing YAML file:")
            if hasattr(exc, 'problem_mark'):
                if exc.context != None:
                    print ('  parser says\n' + str(exc.problem_mark) + '\n  ' +
                        str(exc.problem) + ' ' + str(exc.context))
                else:
                    print ('  parser says\n' + str(exc.problem_mark) + '\n  ' +
                        str(exc.problem))
            else:
                print ("Something went wrong while parsing yaml file")
            # Preserve plain_log for debugging
            copyfile(plain_log, des_dir+"/lava-raw-debug.log")
            sys.exit(1)
        try:
            full_test_log = "{}/{}".format(des_dir, "lava.log")
            opened_logfile["all"] = open(full_test_log, "w")
            for line in log_list:
                level = line["lvl"]
                msg = line["msg"]
                dt  = line["dt"]
                if (level == "target") or (level == "feedback"):

                    namespace = line["ns"] if "ns" in line else "common"
                    if namespace not in opened_logfile:
                        des_log_file = f"{des_dir}/lava-{namespace}.log"
                        opened_logfile[namespace] = open(des_log_file, "w")
                    try:
                        opened_logfile[namespace].write("{}\n".format(msg))
                    except UnicodeEncodeError:
                        msg = (
                            msg
                            .encode("ascii", errors="replace")
                            .decode("ascii")
                        )
                        opened_logfile[namespace].write("{}\n".format(msg))
                # log to 'lava.log'
                opened_logfile["all"].write("{} {}\n".format(dt.split(".")[0], msg))
        except IOError as err:
            print("File Error: " + str(err))

        finally:
            for log_file in opened_logfile:
                opened_logfile[log_file].close()
