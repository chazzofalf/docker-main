#!/bin/bash
DOCKER_FILES=~/docker
docker-stupid-build-profile()
{
	profile="$1"
	failed=1
	while [[ $failed -eq 1 ]]
	do
		failed=0
		while read image_name
		do
			if ! docker-build-image-with-name-stupidly "$image_name"
			then
				failed=1
			fi
		done < <(docker-profile-image-names $profile)
	done
}
docker-image-names()
{
	docker images --format={{.Repository}}:{{.Tag}} | grep "\:latest$" | cut -d: -f 1
}
docker-old-image-tags()
{
	docker images --format={{.Repository}}:{{.Tag}} | grep -v "\:latest$" | grep -v "\:<none>$"
}
docker-remove-old-image-tags()
{
	docker-old-image-tags | xargs docker rmi
}
docker-image-ids()
{
	docker images | while read line ; do echo $line ; done | cut -d\  -f 3 | tail -n +2
}
docker-image-exists()
{
	while read image_name
	do
		if [[ "$1" == "$image_name" ]]
		then
			echo "Image ${1} exists so skipping..."
			return 0
		fi
	done < <(docker-image-names)
	echo "Image ${1} does not exists proceeding..."
	return 1
}
docker-image-clean()
{
	docker-image-ids | while read image
	do
		docker rmi $image
	done	
}
_docker-image-roots()
{
	pushd "$DOCKER_FILES" 2> /dev/null 2> /dev/null > /dev/null
	for f in *
	do
		if [[ -d "$f" ]]
		then
			echo "$f"
		fi
	done
	popd 2> /dev/null > /dev/null
}
docker-image-roots()
{
	out="$(_docker-image-roots)"
	echo "$out"
}
docker-image-rebuild()
{
	docker-image-clear
	docker-build-all
}
docker-build-image-name()
{
	echo $(basename $(dirname $PWD))/$(basename $PWD)
}
_docker-images-in-root()
{
	root_name=$1
	pushd "$DOCKER_FILES" 2> /dev/null > /dev/null
	if [[ -d $root_name ]]
	then
		pushd $root_name 2> /dev/null > /dev/null
		for f in *
		do
			if [[ -d "$f" ]]
			then
				echo "$f"
			fi
		done
		popd 2> /dev/null > /dev/null
	fi
	popd 2> /dev/null > /dev/null
}
docker-images-in-root()
{
	out="$(_docker-images-in-root $1)"
	echo "$out"
}
docker-image-dir-single()
{
	echo "${DOCKER_FILES}/${1}"
}
docker-image-dir()
{
	root=$1
	image=$2
	echo "${DOCKER_FILES}/${root}/${image}"
}
docker-all-image-dirs()
{
	docker-image-roots | while read root
	do
		docker-images-in-root $root | while read image
		do
			docker-image-dir $root $image
		done
	done
}
docker-smart-build()
{
	if [[ ! -f ./build.sh ]]
	then
		docker-smart-build-core "$@"
	else
		if ! docker-image-exists $(docker-build-image-name)
		then
			./build.sh "$@"
		fi
	fi
}
docker-smart-build-core()
{
	if ! docker-image-exists $(docker-build-image-name)
	then
		#echo docker build -t $(docker-build-image-name) "$@" .
		docker build -t $(docker-build-image-name) "$@" .
	fi
}
_docker-all-image-names()
{
	docker-all-image-dirs | while read imagedir
	do
		pushd "$imagedir" 2> /dev/null > /dev/null
		docker-build-image-name
		popd 2> /dev/null > /dev/null
	done
}
docker-all-image-names()
{
	out="$(_docker-all-image-names)"
	echo "$out"
}
docker-build-image-with-name-stupidly()
{
	pushd "$(docker-image-dir-single $1)"
	if ! docker build -t "$1" .
	then
		popd
		return 1
	fi
	popd
	return 0
}
docker-build-image-with-name()
{
	pushd "$(docker-image-dir-single $1)"
	docker-smart-build "${@:2}"
	popd
}
docker-update-all()
{
	docker-all-image-names | while read imagename
	do
		docker tag "$imagename":latest "$imagename":old_asof_`date +%Y%m%d_%H%M%S`
		docker rmi "$imagename":latest
	done
	docker-all-image-names | while read imagename
	do
		docker-build-image-with-name "$imagename" --no-cache
	done
}
docker-refresh-image-with-name()
{
	if [[ ! -z "$1" ]]
	then
		TEMPDIR=$(mktemp)
		rm -r $TEMPDIR
		mkdir $TEMPDIR
		pushd $TEMPDIR
		echo 'FROM '$1 > Dockerfile
		echo 'ENV __OLD_DEBIAN_FRONTEND="$DEBIAN_FRONTEND"' >> Dockerfile
		echo 'ENV DEBIAN_FRONTEND="noninteractive"' >> Dockerfile
		echo 'RUN apt-get update' >> Dockerfile
		echo 'RUN apt-get -yq dist-upgrade' >> Dockerfile
		echo 'ENV DEBIAN_FRONTEND="$__OLD_DEBIAN_FRONTEND"' >> Dockerfile
		docker build -t $1 .
		popd
		rm -r $TEMPDIR
	fi
}
docker-profile-image-names()
{
	docker-all-image-names | grep "${1}"/
}
docker-update-profile()
{
	docker-all-image-names | grep "${1}"/ | while read imagename
	do
		docker tag "$imagename":latest "$imagename":old_asof_`date +%Y%m%d_%H%M%S`
		docker rmi "$imagename":latest
	done
	docker-all-image-names | grep "${1}"/ | while read imagename
	do
		docker rmi --no-prune "$imagename"
		docker-build-image-with-name "$imagename" --no-cache
	done
}
docker-build-all()
{
	docker-all-image-names | while read imagename
	do
		docker-build-image-with-name $imagename "$@"
	done
}
docker-clean-profile()
{
	if [[ ! -z "$1" ]]
	then
		docker-all-image-names | grep "${1}/" | while read imagename
		do
			docker rmi "$imagename"
		done
	else
		echo "Specify profile to clean profile."
	fi
}
docker-rebuild-profile()
{
	if [[ ! -z "$1" ]]
	then
		docker-clean-profile "$1"
		docker-build-profile "$1" "$@"
	else
		echo "Specify profile to rebuild profile."
	fi
}
docker-build-profile()
{
	if [[ -z "$1" ]]
	then
		echo "Specify profile to build profile."
	else
		docker-all-image-names | grep "${1}/" | while read imagename
		do
			docker-build-image-with-name $imagename "${@:2}"
		done
	fi
}

