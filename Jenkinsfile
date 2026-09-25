pipeline {
  agent any 
  triggers {
    pollSCM('H/5 * * * *')
  }


  environment {
    AWS_REGION   = 'us-east-1'
    AWS_ACCOUNT  = '491865087343'
    ECR_REGISTRY = "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    ECR_REPO     = "${ECR_REGISTRY}/devops-challenge2-app"
    CLUSTER_NAME = 'devops-challenge2-cluster'
    RELEASE_NAME = 'hello-app'
    IMAGE_TAG    = "${env.BUILD_NUMBER}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Image') {
      steps {
        // EKS nodes are x86_64; build for amd64 even on an ARM Mac
        sh 'docker build --platform linux/amd64 -t $ECR_REPO:$IMAGE_TAG -t $ECR_REPO:latest app/'
      }
    }

    stage('Push to ECR') {
      steps {
        sh '''
          aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
          docker push $ECR_REPO:$IMAGE_TAG
          docker push $ECR_REPO:latest
        '''
      }
    }

    stage('Deploy to EKS') {
      steps {
        sh '''
          aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
          helm upgrade --install $RELEASE_NAME ./app-chart \
            --set image.repository=$ECR_REPO \
            --set image.tag=$IMAGE_TAG \
            --wait --timeout 5m
          kubectl rollout status deployment/hello-app-app-chart --timeout=120s
        '''
      }
    }

    stage('Verify') {
      steps {
        sh '''
          kubectl get pods -o wide
          kubectl get hpa
          kubectl get ingress
        '''
      }
    }
  }

  post {
    always {
      sh 'docker logout $ECR_REGISTRY || true'
    }
  }
}
