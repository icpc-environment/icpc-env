#!/bin/sh
curl -o /opt/pydev_certificate.cer http://pydev.org/pydev_certificate.cer
keytool -import -file /opt/pydev_certificate.cer -noprompt -storepass changeit -keystore /usr/lib/jvm/jdk*/jre/lib/security/cacerts

/opt/eclipse/eclipse -nosplash \
    -application org.eclipse.equinox.p2.director \
    -repository http://pydev.org/updates/ \
    -destination /opt/eclipse \
    -installIU org.python.pydev.feature.feature.group | grep -v DEBUG
