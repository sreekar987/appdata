#!/bin/bash

LOG=/tmp/stack.log
ID=$(id -u)
MOD_JK_URL=http://www-us.apache.org/dist/tomcat/tomcat-connectors/jk/tomcat-connectors-1.2.44-src.tar.gz
MOD_JK_TAR_FILE=$(echo $MOD_JK_URL | awk -F / '{print $NF}') #$(echo $MOD_JK_URL | cut -d / -f8)
MOD_JK_DIR=$(echo $MOD_JK_TAR_FILE | sed -e 's/.tar.gz//')

TOMCAT_URL=$(curl -s https://tomcat.apache.org/download-90.cgi | grep -A 20 Core: | grep nofollow | grep tar | cut -d '"' -f2)
TOMCAT_TAR_FILE=$(echo $TOMCAT_URL | awk -F / '{print $NF}')
TOMCAT_DIR=$(echo $TOMCAT_TAR_FILE | sed -e 's/.tar.gz//')
STUDENT_WAR_URL=https://github.com/devops2k18/DevOpsDecember/raw/master/APPSTACK/student.war
MYSQL_DRIVER_URL=https://github.com/devops2k18/DevOpsDecember/raw/master/APPSTACK/mysql-connector-java-5.1.40.jar
MYSQL_DRIVER_FILE=$(echo $MYSQL_DRIVER_URL | awk -F / '{print $NF}')

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

if [ $ID -ne 0 ]; then
	echo "You are not the root user, you dont have permissions to run this"
	exit 1
else
	echo "you are the root user"
fi

VALIDATE(){
	if [ $1 -ne 0 ]; then
		echo -e "$2 ... $R FAILED $N"
		exit 1
	else
		echo -e "$2 ... $G SUCCESS $N"
	fi

}

SKIP(){
	echo -e "$1 ... $Y SKIPPING $N"
}

yum install httpd -y &>>$LOG

VALIDATE $? "Installing WebServer"

systemctl start httpd &>>$LOG

VALIDATE $? "Starting the webserver"

if [ -f /opt/$MOD_JK_TAR_FILE ];then
	SKIP "Downloaing the MOD_JK"
else
	wget $MOD_JK_URL -O /opt/$MOD_JK_TAR_FILE &>>$LOG
	VALIDATE $? "Downloaing the MOD_JK"
fi

cd /opt

if [ -d /opt/$MOD_JK_DIR ]; then
	SKIP "Extracting the MOD_JK"
else
	tar -xf $MOD_JK_TAR_FILE &>>$LOG
	VALIDATE $? "Extracting the MOD_JK"
fi

yum install gcc httpd-devel java -y &>>$LOG

VALIDATE $? "Downloaing GCC and httpd-devel"

cd $MOD_JK_DIR/native

if [ -f /etc/httpd/modules/mod_jk.so ]; then
	SKIP "Compiling MOD_JK"
else
	./configure --with-apxs=/bin/apxs &>>$LOG && make &>>$LOG && make install &>>$LOG
	VALIDATE $? "Compiling MOD_JK"
fi

cd /etc/httpd/conf.d

if [ -f /etc/httpd/conf.d/modjk.conf ]; then
	SKIP "creating mod_jk.conf"
else
	echo 'LoadModule jk_module modules/mod_jk.so
	JkWorkersFile conf.d/workers.properties
	JkLogFile logs/mod_jk.log
	JkLogLevel info
	JkLogStampFormat "[%a %b %d %H:%M:%S %Y]"
	JkOptions +ForwardKeySize +ForwardURICompat -ForwardDirectories
	JkRequestLogFormat "%w %V %T"
	JkMount /student tomcatA
	JkMount /student/* tomcatA' > modjk.conf
	VALIDATE $? "creating mod_jk.conf"
fi

if [ -f /etc/httpd/conf.d/workers.properties ]; then
	SKIP "Creating workers.properties"
else
	echo '### Define workers
	worker.list=tomcatA
	### Set properties
	worker.tomcatA.type=ajp13
	worker.tomcatA.host=localhost
	worker.tomcatA.port=8009' > workers.properties
	VALIDATE $? "Creating workers.properties"
fi

systemctl restart httpd &>>$LOG

VALIDATE $? "Restarting the webserver"


if [ -f /opt/$TOMCAT_TAR_FILE ];then
	SKIP "Downloaing TOMCAT"
else
	wget $TOMCAT_URL -O /opt/$TOMCAT_TAR_FILE &>>$LOG
	VALIDATE $? "Downloaing TOMCAT"
fi

cd /opt

if [ -d /opt/$TOMCAT_DIR ]; then
	SKIP "Extracting TOMCAT"
else
	tar -xf $TOMCAT_TAR_FILE
	VALIDATE $? "Extracting TOMCAT"
fi

cd $TOMCAT_DIR/webapps

rm -rf *;

wget $STUDENT_WAR_URL &>>$LOG
VALIDATE $? "Downloaing student.war"

cd ../lib

if [ -f $MYSQL_DRIVER_FILE ]; then
	SKIP "Downloaing MySQL driver"
else
	wget $MYSQL_DRIVER_URL &>>$LOG
	VALIDATE $? "Downloaing MySQL driver"
fi

cd ../conf

sed -i -e '/TestDB/ d' context.xml

sed -i -e '$ i <Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource" maxTotal="100" maxIdle="30" maxWaitMillis="10000" username="student" password="student@1" driverClassName="com.mysql.jdbc.Driver" url="jdbc:mysql://localhost:3306/studentapp"/>' context.xml
			   
VALIDATE $? "Updating the context.xml"

cd ../bin

sh shutdown.sh &>>$LOG
sh startup.sh &>>$LOG

VALIDATE $? "Restarting Tomcat"

yum install mariadb mariadb-server -y &>>$LOG

VALIDATE $? "Installing MariaDB"

systemctl enable mariadb &>>$LOG

systemctl start mariadb

VALIDATE $? "Start mariadb"

echo "create database if not exists studentapp;
use studentapp;
CREATE TABLE if not exists Students(student_id INT NOT NULL AUTO_INCREMENT,
	student_name VARCHAR(100) NOT NULL,
    student_addr VARCHAR(100) NOT NULL,
	student_age VARCHAR(3) NOT NULL,
	student_qual VARCHAR(20) NOT NULL,
	student_percent VARCHAR(10) NOT NULL,
	student_year_passed VARCHAR(10) NOT NULL,
	PRIMARY KEY (student_id)
);
grant all privileges on studentapp.* to 'student'@'localhost' identified by 'student@1';" > /tmp/student.sql

VALIDATE $? "Creating student.sql"

mysql < /tmp/student.sql

VALIDATE $? "Created student schema and tables"


