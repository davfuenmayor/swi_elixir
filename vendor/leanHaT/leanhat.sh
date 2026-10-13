#!/bin/sh
#-----------
# File:      leanhat.sh
# Version:   1.0
# Date:      1 April 2025
#-----------
# Purpose:   Invokes the leanHaT prover
# Usage:     ./leanhat.sh <problem file>
# Author:    Jens Otten
# Web:       www.leancop.de/leanhat/
# Copyright: (c) 2025 by Jens Otten
# License:   GNU General Public License
#-----------

#-----------
# Parameters

# set logic [ht]
LOGIC=ht

# set leanHaT prover path
PROVER_PATH=.

# set Prolog system, path, and options

PROLOG=eclipse
PROLOG_PATH=/usr/bin/eclipse
PROLOG_OPTIONS='-e'

#PROLOG=swi
#PROLOG_PATH=/usr/bin/swipl
#PROLOG_OPTIONS='-O -q -g'

# Proof output is currently not supported!
# print proof [yes|no]
PRINT_PROOF=no
# save proof [yes|no]
SAVE_PROOF=no
# proof layout [compact|readable]
PROOF_LAYOUT=compact

# set TPTP library path
# export TPTP=.


#-------------
# Main Program

if [ $# -eq 0 -o $# -gt 1 ]; then
 echo "Usage: $0 <problem file>"
 exit 2
fi

if [ ! -r "$1" ]; then
 echo "Error: File $1 not found" >&2
 exit 2
fi

FILE=$1

#----------
# Functions

  $PROLOG_PATH $PROLOG_OPTIONS \
  "assert(prolog('$PROLOG')),\
   assert(proof('$PROOF_LAYOUT')),\
   ['$PROVER_PATH/leanhat_main.pl'],\
   asserta(logic('$LOGIC')),\
   leanhat_main('$FILE',[],_),\
   halt."

