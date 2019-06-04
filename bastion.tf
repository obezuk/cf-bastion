provider "cloudflare" {
  email = "${var.cloudflare_email}"
  token = "${var.cloudflare_token}"
}

resource "cloudflare_access_application" "bastion-web" {
  zone_id          = "${var.cloudflare_zone_id}"
  name             = "Bastion Web"
  domain           = "bastion-web.${var.cloudflare_zone}"
}

resource "cloudflare_access_application" "bastion-ssh" {
  zone_id          = "${var.cloudflare_zone_id}"
  name             = "Bastion SSH"
  domain           = "bastion-ssh.${var.cloudflare_zone}"
}

resource "cloudflare_access_policy" "bastion-web-policy" {
  application_id = "${cloudflare_access_application.bastion-web.id}"
  zone_id        = "${var.cloudflare_zone_id}"
  name           = "Internal Staff Web Access"
  precedence     = "1"
  decision       = "allow"
  include = {
    email_domain = ["cloudflare.com"]
  }
}

resource "cloudflare_access_policy" "bastion-ssh-policy" {
  application_id = "${cloudflare_access_application.bastion-ssh.id}"
  zone_id        = "${var.cloudflare_zone_id}"
  name           = "Internal Staff SSH Access"
  precedence     = "1"
  decision       = "allow"
  include = {
    email_domain = ["cloudflare.com"]
  }
}

provider "aws" {
  region = "ap-southeast-2"
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}" 
}

resource "aws_security_group" "security-group" {

    name = "bastion"
    description = "AWS security group for terraform example"

    ingress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }

    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }

}

variable "aws_amis" {
    default = {
        ap-southeast-2 = "ami-0fb7513bcdc525c3b"
    }
}

resource "aws_instance" "bastion" {
  key_name = "${var.aws_key_name}"
  instance_type = "t2.nano"
  security_groups = [ "${aws_security_group.security-group.name}" ]
  ami = "${lookup(var.aws_amis, "ap-southeast-2")}"

  connection {
      host = "${aws_instance.bastion.public_ip}"
      user = "${var.aws_instance_user}"
      private_key = "${file(var.aws_key_path)}"
  }

  provisioner "file" {
    source      = "cert.pem"
    destination = "/home/ec2-user/cloudflared-cert.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y docker",
      "sudo service docker start",
      "sudo docker run -d --restart always --name=netdata -p 19999:19999 -v /proc:/host/proc:ro -v /sys:/host/sys:ro -v /var/run/docker.sock:/var/run/docker.sock:ro --cap-add SYS_PTRACE --security-opt apparmor=unconfined netdata/netdata",
      "sudo docker run -d --restart always --name=argo_tunnel_ssh --net=host -v /home/ec2-user/cloudflared-cert.pem:/etc/cloudflared/cert.pem obezuk/cloudflared-docker --hostname bastion-ssh.${var.cloudflare_zone} --url ssh://localhost:22",
      "sudo docker run -d --restart always --name=argo_tunnel_web --net=host -v /home/ec2-user/cloudflared-cert.pem:/etc/cloudflared/cert.pem obezuk/cloudflared-docker --hostname bastion-web.${var.cloudflare_zone} --url http://localhost:19999"
    ]
  }

}