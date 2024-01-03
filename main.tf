locals {
name      = "k8cstafod"
prvtsub01 = "subnet-0d60aefb99f7c1456"
prvtsub02 = "subnet-063536ec9ebc5edf7"
prvtsub03 = "subnet-0c1bab015ca874cb1"
pubsub01-id = "subnet-09e8e0cf73480d587"
pubsub02-id = "subnet-02eb67fd3ad389d4d"
pubsub03-id = "subnet-0c762c92510e5f8e4"
vpc-id = "vpc-0ac24921d840f58a3"
}

data "aws_vpc" "vpc" {
  id = local.vpc-id
}
data "aws_subnet" "pubsub01" {
  id = local.pubsub01-id
}
data "aws_subnet" "pubsub02" {
  id = local.pubsub02-id
}
data "aws_subnet" "pubsub03" {
  id = local.pubsub03-id
}
data "aws_subnet" "prvtsub01" {
  id = local.prvtsub01
}
data "aws_subnet" "prvtsub02" {
  id = local.prvtsub02
}
data "aws_subnet" "prvtsub03" {
  id = local.prvtsub03
}

module "bastion" {
  source        = "./module/bastion"
  ami           = "ami-0e5f882be1900e43b"
  instance_type = "t2.micro"
  subnets       = data.aws_subnet.pubsub01.id
  bastion-sg    = module.sg-keypair.bastion-sg
  key_name      = module.sg-keypair.keypair-id
  private-key   = module.sg-keypair.private-key
  tag-bastion   = "${local.name}-bastion"
}

module "masternodes" {
  source          = "./module/masternode"
  instance-count  = 3
  ami             = "ami-0e5f882be1900e43b"
  instance_type   = "t2.medium"
  k8-sg           = [module.sg-keypair.k8s-sg]
  subnet_id       = [data.aws_subnet.prvtsub01.id, data.aws_subnet.prvtsub02.id, data.aws_subnet.prvtsub03.id]
  key_name        = module.sg-keypair.keypair-id
  tag-masternodes = "${local.name}-masternode"
}

module "ansible" {
  source        = "./module/ansible"
  ami           = "ami-0e5f882be1900e43b"
  instance_type = "t2.micro"
  subnet_id     = data.aws_subnet.prvtsub01.id
  ansible-sg    = [module.sg-keypair.ansible-sg]
  key_name      = module.sg-keypair.keypair-id
  private-key   = module.sg-keypair.private-key
  haproxy1      = module.haproxy.haproxy1_private_ip
  haproxy2      = module.haproxy.haproxy2_private_ip
  main-master   = module.masternodes.masternodes-privateip[0]
  member-master01   = module.masternodes.masternodes-privateip[1]
  member-master02   = module.masternodes.masternodes-privateip[2]
  worker01 = module.workernodes.workernodes-privateip[0]
  worker02 = module.workernodes.workernodes-privateip[1]
  worker03 = module.workernodes.workernodes-privateip[2]
  bastion-host = module.bastion.bastion_public_ip
  instance-name = "${local.name}-ansible"
}

module "workernodes" {
  source        = "./module/workernodes"
  ami           = "ami-0e5f882be1900e43b"
  instance-type = "t2.medium"
  k8-sg         = [module.sg-keypair.k8s-sg]
  prvsubnet     = [data.aws_subnet.prvtsub01.id, data.aws_subnet.prvtsub02.id, data.aws_subnet.prvtsub03.id]
  keypair       = module.sg-keypair.keypair-id
  workernodes   = "${local.name}-workernodes"
}

module "sg-keypair" {
  source     = "./module/sg-keypair"
  vpc-id     = data.aws_vpc.vpc.id
  k8s-sg     = "${local.name}-k8s-sg"
  ansible-sg = "${local.name}-ansible-sg"
  bastion-sg = "${local.name}-bastion-sg"
}

module "haproxy" {
  source        = "./module/haproxy"
  ami           = "ami-0e5f882be1900e43b"
  instance_type = "t2.medium"
  subnets       = data.aws_subnet.prvtsub01.id
  subnets2      = data.aws_subnet.prvtsub02.id
  haproxy-sg    = module.sg-keypair.k8s-sg
  key_name      = module.sg-keypair.keypair-id
  tag-haproxy1  = "${local.name}-haproxy1"
  tag-haproxy2  = "${local.name}-haproxy2"
  master1       = module.masternodes.masternodes-privateip[0]
  master2       = module.masternodes.masternodes-privateip[1]
  master3       = module.masternodes.masternodes-privateip[2]
}


module "environment-lb" {
  source        = "./module/environment-lb"
  vpc-id        = data.aws_vpc.vpc.id
  prodtg        = "${local.name}-prod-tg"
  stage-tg-name = "${local.name}-stage-tg"
  instance      = module.workernodes.workernodes-id
  lb-sg         = [module.sg-keypair.k8s-sg]
  subnet-id     = [data.aws_subnet.pubsub01.id, data.aws_subnet.pubsub02.id, data.aws_subnet.pubsub03.id]
  tag-stage-alb = "${local.name}-stage-alb"
  tag-prod-alb  = "${local.name}-prod-alb"
  certificate_arn = module.route53.certificate-arn
}

module "monitoring-lb" {
  source         = "./module/monitoring-lb"
  graf-tg        = "${local.name}-graf-tg"
  prom-tg        = "${local.name}-prom-tg"
  vpc_id         = data.aws_vpc.vpc.id
  subnets        = [data.aws_subnet.pubsub01.id, data.aws_subnet.pubsub02.id, data.aws_subnet.pubsub03.id]
  tag-grafana_lb = "${local.name}-grafana"
  tag-prom-lb    = "${local.name}-prometheus"
  k8s            = [module.sg-keypair.k8s-sg]
  instance       = module.workernodes.workernodes-id
  certificate_arn = module.route53.certificate-arn
}

module "route53" {
  source            = "./module/route53-ssl"
  domain-name       = "funmibideji-cloud.link"
  domain-name1      = "stage.funmibideji-cloud.link"
  domain-name2      = "prod.funmibideji-cloud.link"
  domain-name3      = "graf.funmibideji-cloud.link"
  domain-name4      = "prom.funmibideji-cloud.link"
  domain-name5      = "*.funmibideji-cloud.link"
  stage_lb_dns_name = module.environment-lb.stage-dns-name
  stage_lb_zoneid   = module.environment-lb.stage-zoneid
  prod_lb_dns_name  = module.environment-lb.prod-dns-name
  prod_lb_zoneid    = module.environment-lb.prod-zoneid
  graf_lb_dns_name  = module.monitoring-lb.grafana-dns-name
  graf_lb_zoneid    = module.monitoring-lb.grafana-zone_id
  prom_lb_dns_name  = module.monitoring-lb.prometheus-dns-name
  prom_lb_zoneid    = module.monitoring-lb.prom-zoneid
}