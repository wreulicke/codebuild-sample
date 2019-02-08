こんにちは。齋藤です。

[CloudWatch Event](https://aws.amazon.com/jp/about-aws/whats-new/2017/12/amazon-cloudwatch-events-now-supports-aws-codebuild-as-an-event-target/)が
CodeBuildに 対応しました。
そこで、今日は CodeBuildとCloudWatch Eventを組み合わせて
Docker Imageをデイリーでビルドするようにしてみます。
デイリーでビルドすることで、常に最新のイメージが使えることになります。

次のような流れでセットアップしていきます。

* Dockerfileを書く
* CodeBuildの設定を書く
* マネージメントコンソールからCodeBuildでビルドプロジェクトの設定をする
* IAMのポリシーに設定を追加する
* CloudWatchイベントの設定をする

AWSのCodeBuildを使って ECRやDockerHubに push するサンプルは[公式ドキュメント](http://docs.aws.amazon.com/ja_jp/codebuild/latest/userguide/sample-docker.html)にもあります。
内容としてはこちらをベースにやっていきます。

CodeBuildのビルドの入力としては S3、GitHub、CodeCommit、BitBucketと選べるのですが
今回は GitHubの個人アカウントを使うことにします。

最終的なリポジトリの最小構成としては以下のような形になりました。

```
$ tree
.
├── Dockerfile
└── buildspec.yml
```

今回ローカルでは次のような環境で動かしましたが
基本的には Dockerコンテナの上でビルドをします。

```
$ docker version
Client:
 Version:      17.09.1-ce
 API version:  1.32
 Go version:   go1.8.3
 Git commit:   19e2cf6
 Built:        Thu Dec  7 22:22:25 2017
 OS/Arch:      darwin/amd64

Server:
 Version:      17.09.1-ce
 API version:  1.32 (minimum version 1.12)
 Go version:   go1.8.3
 Git commit:   19e2cf6
 Built:        Thu Dec  7 22:28:28 2017
 OS/Arch:      linux/amd64
 Experimental: true
```

また、今回は ECRのリポジトリが存在する前提で話を進めさせていただきます。ご了承ください。

## Dockerfileを書きます

次のようなDockerfileを用意しました。
openjdk:8-jdk-alpine を ベースに
git と ssh を追加するイメージです。

```dockerfile
FROM openjdk:8-jdk-alpine

RUN apk add --no-cache \
        openssh \
        git
```

特に凝ったことはしてませんね。
このファイルをルートディレクトリに置いておきます。
ローカルでビルドしてビルドが失敗しないかだけ確認しておきましょう。

```
docker build -t .
```
## CodeBuildの設定を書く

CodeBuildでは ビルドは何をするのか、とビルドの環境はどうするのか、と言う設定が分かれております。

ここでいう CodeBuildの設定は 「ビルドは何をするのか」ということについてです。

次のような設定ファイルを用意しておきます。

```yml
version: 0.1
phases:
  pre_build: # ecrにログイン
    commands:
      - echo Logging in to Amazon ECR...
      - $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email) # docker のバージョンによって --no-include-emailが必要
  build: # イメージのビルドとタグ付け
    commands:
      - echo Build started on `date`
      - echo Building the Docker image...          
      - docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .
      - docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG      
  post_build: # イメージの push
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker image...
      - docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
```

上記で用意した設定ファイルではいくつかの環境変数を用いています。

* $AWS_DEFAULT_REGION: ECRのリポジトリがあるリージョン
* $IMAGE_REPO_NAME: ECRのリポジトリ名
* $IMAGE_TAG: イメージのタグ名
* $AWS\_ACCOUNT\_ID: AWSアカウントのID
 
CodeBuildで ビルドプロジェクトの設定の際に必要になります。

## CodeBuildでビルドプロジェクトの設定をする

今回はマネージメントコンソールから CodeBuildの設定をしてみます。

まずは CodeBuildの次のような画面に飛んで、「プロジェクトの作成」ボタンを押します。
初めての方は別の画面が出るかもしれません。

### ビルドプロジェクト名の設定と リポジトリの連携
## TODO create-project

ビルドプロジェクトの名前を入力したら
GitHubを選択します。

## TODO github

GitHubを選択したら、初めての場合、OAuth2での連携をするためのボタンが表示されます。
このボタンを押して、出てきたウィンドウを進めて連携をします。

## TODO connect-github

何はともあれ、連携が終わったら、リポジトリの選択を行います。
ここでは事前に用意しておいた「codebuild-sample」を選びました。

## TODO select-repository

また、コミット時のWebHookによるビルドも行いたいので
「コードの変更がレポジトリにプッシュされるたびに再構築する」のチェックを入れておきます。
## TODO repository

### ビルド環境の設定

今度は ビルド環境の設定です。

大体デフォルトの設定ですが、次のような設定をしておきます。

CodeBuildで用意されているイメージは awscliや所定のコマンドが入っており便利です。

今回は Dockerのイメージのビルドをするので

aws/codebuild/Docker:17.09.0 のイメージを使います。

## TODO build

この画面で buildspec.yml相当の記述も出来ますが
今回は 事前に準備しているので、単に buildspec.ymlを使うようにします。

### ビルド時の IAM roleの設定

ビルド時の IAM Roleの設定を行います。

コンソールでIAM Roleを作ってくれるので、これを使います。
しかし、今回はビルドでECR に pushするので設定を追加しないとビルドがエラーになります。
この設定は後で追加します。

## TODO role


### ビルド時の環境変数の設定

今度は環境変数の設定です。

## TODO environment-settings

やりました。
再掲しておきます。

* $AWS_DEFAULT_REGION: ECRのリポジトリがあるリージョン
* $IMAGE_REPO_NAME: ECRのリポジトリ名
* $IMAGE_TAG: イメージのタグ名
* $AWS\_ACCOUNT\_ID: AWSアカウントのID

### これでビルドのプロジェクトの作成は終了です

最後に「続行」ボタンを押した後、確認画面が出ます。

## TODO verify

「保存してビルド」を押下します。すると次のような画面に飛ぶので
「ビルドの開始」を押下します。

ここでは、設定したポリシーに ECR に ログインする権限がないので
エラーになると思います。

### IAM Roleに ECRの設定を追加する

こちらの内容は 公式ドキュメントにも書いております。

IAM Roleの画面に飛んで
設定を追加しておきましょう。

再度ビルドの開始を行うとECRへの ログインに成功してイメージのビルド、pushに成功するはずです。

## CloudWatch イベントの設定を追加して、デイリービルドするようにする

CodeBuildのARNの指定方法は[いくつか指定方法があります](http://docs.aws.amazon.com/ja_jp/codebuild/latest/userguide/auth-and-access-control-iam-access-control-identity-based.html#arn-formats)が
今回は単純にプロジェクトのビルドをやっていきますので
次のような形になります。

```
arn:aws:codebuild:region-ID:account-ID:project/project-name
```

と言うわけで次のような形になりました

```
arn:aws:codebuild:ap-northeast-1:<your-account-id>:project/codebuild-test2
```

## TODO CloudWatch

設定をすると
指定の時間にビルドがこんな感じで走ります。（画像はイメージです。）

## TODO build log

## まとめ

今回はコンソールから、CloudWatchイベントのスケジューリングイベントを使って
Dockerイメージをビルドするような設定をしてみました。

便利ですね。

docker のバージョンによって --no-include-emailが必要なことに注意してください。

Happy Hacking!!