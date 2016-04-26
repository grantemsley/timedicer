#!/usr/bin/python
# Script by Grant Emsley <grant@emsley.ca> to create rdiffweb users from the command line
# Written 2016-04-23
#
# Usage: ./rdiffweb-adduser.py username -p password -d /home/username -e user@example.com
#
# Script will create an rdiffweb account with the specified username, and optionally a password, home directory and email address.
# Since it uses the actual rdiffweb code, it will work no matter what database is being used.
#
# Copyright 2016 Grant Emsley
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
from rdiffweb.rdw_app import RdiffwebApp

parser = argparse.ArgumentParser(description='Create rdiffweb user account.')
parser.add_argument('username',type=unicode)
parser.add_argument('-p','--password',type=unicode)
parser.add_argument('-d','--homedir',type=unicode)
parser.add_argument('-e','--email',type=unicode)
args = parser.parse_args()


app = RdiffwebApp("/etc/rdiffweb/rdw.conf")
# Create user with specified password
app.userdb.add_user(args.username, args.password)

# Optionally set home directory and email address
if args.homedir is not None:
        app.userdb.set_user_root(args.username, args.homedir)
if args.email is not None:
        app.userdb.set_email(args.username, args.email)
