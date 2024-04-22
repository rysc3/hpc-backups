#!/bin/bash

srun -p gpu -G 1 --account=ka1273 -N 1 --exclusive --pty bash 

source ~/env.sh
