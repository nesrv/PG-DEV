prnusage() {
	cat <<- USG
	This script simulates manual execution of commands included in practice solutions.
	Usage:
	  $0 [lab|opt|app]
	USG
}

if [ $# -gt 1 ]; then
	prnusage
	exit 1
fi

case $1 in
	lab|opt|app)
		suffix=$1
		log=`pwd`/run_solutions.${1}.log
		;;
	*)
		prnusage
		exit 1
esac

~/reset.sh
cd ~/${course}/labs
#for i in ${course}*_${suffix}.sh; do echo $i; done | sort | while read i
for i in $(ls ${course}*_${suffix}.sh)
do
	echo -e "\n########## $(basename $i) ##########\n"
	./$i --non-interactive --only-visible
done | tee $log
