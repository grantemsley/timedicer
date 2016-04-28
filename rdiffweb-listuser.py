#!/usr/bin/python
# Script by Grant Emsley <grant@emsley.ca>
# Written 2016-04-23
#
# Usage: ./rdiffweb-listuser.py
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

parser = argparse.ArgumentParser(description='List rdiffweb users.')
args = parser.parse_args()

app = RdiffwebApp("/etc/rdiffweb/rdw.conf")
# Create user with specified password
users = app.userdb.list()

for user in users:
	email = app.userdb.get_email(user)
	home = app.userdb.get_user_root(user)
	print "%s, %s, %s" %(user, email, home)
