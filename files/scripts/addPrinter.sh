#!/bin/bash

# Clear out all old printers
for PRINTER in $(lpstat -v | cut -d ' ' -f 3 | tr -d ':')
do
  lpadmin -x $PRINTER
done
lpadmin -x ContestPrinter

# Ask the user to add printers(loops until they enter 0.0.0.0)
i=0
adding=0
while true; do
	printerIP=$(zenity --entry --title="Adding Printers..." --text="Enter Printer IP:" --entry-text="0.0.0.0")
	if [ $printerIP != "0.0.0.0" ]
	then
		lpadmin -p Printer$i -v socket://$printerIP -E -m drv:///sample.drv/generic.ppd
		lpadmin -p Printer$i -c ContestPrinter
		cupsenable Printer$i
		accept Printer$i
		adding=1
	else
		break
	fi
	let i++
done

if [ $adding -ne '0' ]
then
	lpadmin -d ContestPrinter
	cupsenable ContestPrinter
	accept ContestPrinter
fi
