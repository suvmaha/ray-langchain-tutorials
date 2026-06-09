from aws_cdk import (
    Stack,
    CfnOutput,
    Tags,
    aws_ec2 as ec2,
)
from constructs import Construct

CLUSTER_NAME = "eks-ray-platform"


class EksRayStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ── VPC ────────────────────────────────────────────────────────────────
        # 2 AZs, 1 NAT gateway (lab cost optimization).
        # Private subnets: EKS nodes and Ray pods.
        # Public subnets: load balancers.

        vpc = ec2.Vpc(self, "EksRayVpc",
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,  # 251 IPs — sufficient for load balancers
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    # /24 = 251 usable IPs per AZ — fine for tutorials.
                    # For production or large Ray clusters (many workers),
                    # increase to cidr_mask=20 (4096 IPs) before first deploy.
                    cidr_mask=24,
                ),
            ],
        )

        for subnet in vpc.public_subnets:
            Tags.of(subnet).add(f"kubernetes.io/cluster/{CLUSTER_NAME}", "shared")
            Tags.of(subnet).add("kubernetes.io/role/elb", "1")

        for subnet in vpc.private_subnets:
            Tags.of(subnet).add(f"kubernetes.io/cluster/{CLUSTER_NAME}", "shared")
            Tags.of(subnet).add("kubernetes.io/role/internal-elb", "1")

        # ── Outputs ─────────────────────────────────────────────────────────────
        # scripts/create-cluster.sh reads these via CloudFormation describe-stacks.

        CfnOutput(self, "VpcId",
            value=vpc.vpc_id,
            description="VPC ID for eksctl cluster config",
        )
        CfnOutput(self, "PrivateSubnetIds",
            value=",".join([s.subnet_id for s in vpc.private_subnets]),
            description="Private subnet IDs (comma-separated)",
        )
        CfnOutput(self, "PublicSubnetIds",
            value=",".join([s.subnet_id for s in vpc.public_subnets]),
            description="Public subnet IDs for load balancers (comma-separated)",
        )
        CfnOutput(self, "ClusterName",
            value=CLUSTER_NAME,
            description="EKS cluster name",
        )
