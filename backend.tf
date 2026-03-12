terraform {
 backend "s3" {
 bucket = "tf-state-lab3-hevalo-yuliia-05" 
 key = "env/dev/var-05.tfstate" 
 region = "eu-central-1"
 encrypt = true
 use_lockfile = true 
 }
}
