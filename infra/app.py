#!/usr/bin/env python3
import os
import aws_cdk as cdk
from eks_ray.eks_ray_stack import EksRayStack

app = cdk.App()

EksRayStack(app, "EksRayStack",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION"),
    ),
)

app.synth()
