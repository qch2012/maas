pipeline {
  agent any
  stages {
    stage('build') {
      steps {
        echo '"Begin"'
      }
    }

    stage('syntax check') {
      steps {
        sh 'bash -n maas.sh'
      }
    }

  }
}