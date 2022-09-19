#!/usr/bin/env python3
#
# Copyright (c) 2019-2022 Arm Limited. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#

# This script parse the gerrit query results from the stdin
# and return the correct refspec

import sys
import json

def print_topic_tip(query_results):
    patchsets = []
    parents = []
    project = query_results[0]["project"]
    topic = query_results[0]["topic"]

    # For each change, get its most recent patchset
    for change in query_results:
        patchsets.append(change["patchSets"][-1])

    # For each patchset, get its parent commit
    for patchset in patchsets:
        parents.append(patchset["parents"][0])

    # If a patchset's revision is NOT in the list of parents then it should
    # be the tip commit
    tips = list(filter(lambda x: x["revision"] not in parents, patchsets))

    # There must be only one patchset remaining, otherwise the tip is ambiguous
    if len(tips) > 1:
        raise Exception("{} in {} has no unique tip commit.".format(topic, project))
    if len(tips) == 0:
        raise Exception("No tip commit found for {} in {}.".format(topic, project))
    # Print the reference of the topic tip patchset
    print(tips[0]["ref"])

try:
    changes = [json.loads(resp_line) for resp_line in sys.stdin]
except:
    raise Exception("Input error, it's not a JSON string!")

# The last object is a summary; drop it as it's not of interest to us.
changes.pop()

if not changes:
    raise Exception("Can not find anything.")

if len(changes) > 1:
   print_topic_tip(changes)
else:
    print(changes[0]["currentPatchSet"]["ref"])
