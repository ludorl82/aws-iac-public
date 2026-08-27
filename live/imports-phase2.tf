# Import blocks for phase 2. These are declarative and idempotent: once a
# resource is in state, its import block is a no-op. Keep them in git as a
# record of what was adopted rather than deleting them after the first apply.
#
# Deliberately NOT imported: sg-0aaaaaaaaaaaaaaa3 (launch-wizard-1). It is
# attached to nothing and allows SSH from 0.0.0.0/0 and ::/0. Delete it rather
# than adopting it — see README.

import {
  to = aws_vpc.main
  id = "vpc-0aaaaaaaaaaaaaaa1"
}

import {
  to = aws_internet_gateway.main
  id = "igw-0aaaaaaaaaaaaaaa1"
}

import {
  to = aws_subnet.a
  id = "subnet-0aaaaaaaaaaaaaaa2"
}

import {
  to = aws_subnet.b
  id = "subnet-0aaaaaaaaaaaaaaa1"
}

# aws_default_route_table imports by the VPC id, not the rtb- id — the
# provider resolves the VPC's default table itself. Importing by rtb- id fails
# with an unattributed "empty result" at the end of the plan.
import {
  to = aws_default_route_table.main
  id = "vpc-0aaaaaaaaaaaaaaa1"
}

import {
  to = aws_route_table_association.a
  id = "subnet-0aaaaaaaaaaaaaaa2/rtb-0aaaaaaaaaaaaaaa1"
}

import {
  to = aws_route_table_association.b
  id = "subnet-0aaaaaaaaaaaaaaa1/rtb-0aaaaaaaaaaaaaaa1"
}

import {
  to = aws_default_security_group.default
  id = "sg-0aaaaaaaaaaaaaaa2"
}

import {
  to = aws_security_group.main
  id = "sg-0aaaaaaaaaaaaaaa1"
}

import {
  to = aws_eip.aws_node
  id = "eipalloc-0aaaaaaaaaaaaaaa2"
}
