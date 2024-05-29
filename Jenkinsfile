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
        sh 'for script in $(find . -name "*.sh"); do bash -n $script; done'
      }
    }

  }
}