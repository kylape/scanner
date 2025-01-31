// Copyright 2015 clair authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package database

// DebianReleasesMapping translates Debian code names and class names to version numbers.
// If you add a new release here, remember to add it to pkg/wellknownnamespaces/set.go
// as well.
var DebianReleasesMapping = map[string]string{
	// Code names
	"squeeze":  "6",
	"wheezy":   "7",
	"jessie":   "8",
	"stretch":  "9",
	"buster":   "10",
	"bullseye": "11",
	"bookworm": "12",
	"trixie":   "13",
	"sid":      "unstable",

	// Class names
	"oldoldstable": "10",
	"oldstable":    "11",
	"stable":       "12",
	"testing":      "13",
	"unstable":     "unstable",
}

// UbuntuReleasesMapping translates Ubuntu code names to version numbers.
// If you add a new release here, remember to add it to pkg/wellknownnamespaces/set.go
// as well.
var UbuntuReleasesMapping = map[string]string{
	"precise": "12.04",
	"quantal": "12.10",
	"raring":  "13.04",
	"saucy":   "13.10",
	"trusty":  "14.04",
	"utopic":  "14.10",
	"vivid":   "15.04",
	"wily":    "15.10",
	"xenial":  "16.04",
	"yakkety": "16.10",
	"zesty":   "17.04",
	"artful":  "17.10",
	"bionic":  "18.04",
	"cosmic":  "18.10",
	"disco":   "19.04",
	"eoan":    "19.10",
	"focal":   "20.04",
	"groovy":  "20.10",
	"hirsute": "21.04",
	"impish":  "21.10",
	"jammy":   "22.04",
	"kinetic": "22.10",
	"lunar":   "23.04",
	"mantic":  "23.10",
}
