#!/bin/sh
/opt/eclipse/eclipse -nosplash \
    -application org.eclipse.equinox.p2.director \
    -repository http://pydev.org/updates/ \
    -destination /opt/eclipse \
    -installIU org.python.pydev.feature.feature.group | grep -v DEBUG
