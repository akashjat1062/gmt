#!/usr/bin/env bash
#
# Copyright (c) 2012-2020
# by the GMT Team (https://www.generic-mapping-tools.org/team.html)
# See LICENSE.TXT file for copying and redistribution conditions.
#
# Below, <TAG> is either core, supplements, or a users custom shared lib tag
#
# This script will find all the C files in the current dir (if core)
# or in subdirs (if supplements) and extract all the THIS_MODULE_PURPOSE
# and other strings from the sources files, then create one file:
# 	gmt_<TAG>_module.h	Function prototypes (required for Win32)
# 	gmt_<TAG>_module.c	Look-up functions
#
# Note: gmt_<TAG>_module.[ch] are in GitHub.  Only rerun this
# script when there are changes in the code, e.g. a new module.
#
if [ $# -ne 1 ]; then
cat << EOF
usage: gmt_make_module_src.sh [tag]
	tag is the name of the set of modules.
	Choose between core or supplements.
EOF
	exit 0
fi
set -e

LIB=$1
# Make sure we get both upper- and lower-case versions of the tag
U_TAG=$(echo $LIB | tr '[a-z]' '[A-Z]')
L_TAG=$(echo $LIB | tr '[A-Z]' '[a-z]')

if [ "$U_TAG" = "SUPPLEMENTS" ]; then	# Look in directories under the current directory and set LIB_STRING
	grep "#define THIS_MODULE_LIB		" */*.c | gawk -F: '{print $1}' | sort -u > /tmp/tmp.lis
	LIB_STRING="GMT suppl: The official supplements to the Generic Mapping Tools"
elif [ "$U_TAG" = "CORE" ]; then	# Just look in current dir and set LIB_STRING
	grep "#define THIS_MODULE_LIB		" *.c | egrep -v '_mt|_old|_experimental' | gawk -F: '{print $1}' | sort -u > /tmp/tmp.lis
	LIB_STRING="GMT core: The main modules of the Generic Mapping Tools"
else
	echo "Error: Tag must be either core or supplements"
	exit
fi
rm -f /tmp/MNAME.lis /tmp/CNAME.lis /tmp/LIB.lis /tmp/PURPOSE.lis /tmp/KEYS.lis /tmp/all.lis
while read program; do
	grep "#define THIS_MODULE_MODERN_NAME" $program    | gawk '{print $3}' | sed -e 's/"//g' >> /tmp/MNAME.lis
	grep "#define THIS_MODULE_CLASSIC_NAME" $program    | gawk '{print $3}' | sed -e 's/"//g' >> /tmp/CNAME.lis
	grep "#define THIS_MODULE_LIB" $program     | gawk '{print $3}' | sed -e 's/"//g' >> /tmp/LIB.lis
	grep "#define THIS_MODULE_PURPOSE" $program | sed -e 's/#define THIS_MODULE_PURPOSE//g' | gawk '{print $0}' >> /tmp/PURPOSE.lis
	grep "#define THIS_MODULE_KEYS" $program    | sed -e 's/#define THIS_MODULE_KEYS//g' | gawk '{print $0}' >> /tmp/KEYS.lis
done < /tmp/tmp.lis
# Prepend group+name so we can get a list sorted on group name then individual programs
paste /tmp/LIB.lis /tmp/MNAME.lis /tmp/CNAME.lis | gawk '{printf "%s%s |%s\t%s\n", $1, $2, $2, $3}' > /tmp/SORT.txt
paste /tmp/SORT.txt /tmp/LIB.lis /tmp/PURPOSE.lis /tmp/KEYS.lis | sort -k1 -u > /tmp/SORTED.txt
gawk -F"|" '{print $2}' /tmp/SORTED.txt > /tmp/$LIB.txt
rm -f /tmp/tmp.lis /tmp/MNAME.lis /tmp/CNAME.lis /tmp/LIB.lis /tmp/PURPOSE.lis /tmp/SORTED.txt /tmp/SORT.txt /tmp/KEYS.lis

# The output files produced
FILE_GMT_MODULE_C=gmt_${L_TAG}_module.c
FILE_GMT_MODULE_H=gmt_${L_TAG}_module.h
FILE_GMT_MODULE_R=module_${L_TAG}_purpose.rst_

COPY_YEAR=$(date +%Y)

#
# Generate FILE_GMT_MODULE_R
#
# $1 = mname, $2 = cname, $3 = ${L_TAG}, $4 = tab, $5 = purpose, $6 = tab, $7 = keys

if [ "$U_TAG" = "CORE" ]; then
	RSTDIR=../doc/rst/source
else
	RSTDIR=../doc/rst/source/supplements
fi
gawk '
	BEGIN {
		FS = "\t";
	}
	{ printf ".. |%s_purpose| replace:: %s\n.. |%s_purpose| replace:: %s\n", $1, substr($5,2,length($5)-2), $2, substr($5,2,length($5)-2);
}' /tmp/$LIB.txt | sort -u | gawk '{printf "%s\n\n", $0}' > ${RSTDIR}/${FILE_GMT_MODULE_R}

#
# Generate FILE_GMT_MODULE_H
#

cat << EOF > ${FILE_GMT_MODULE_H}
/*
 * Copyright (c) 2012-${COPY_YEAR} by the GMT Team (https://www.generic-mapping-tools.org/team.html)
 * See LICENSE.TXT file for copying and redistribution conditions.
 */

/* gmt_${L_TAG}_module.h declares the prototypes for ${L_TAG} module functions
 * and the array that contains ${L_TAG} GMT module parameters such as name
 * and purpose strings.
 * DO NOT edit this file directly! Regenerate thee file by running
 * 	gmt_make_module_src.sh ${L_TAG}
 */

#pragma once
#ifndef GMT_${U_TAG}_MODULE_H
#define GMT_${U_TAG}_MODULE_H

#ifdef __cplusplus /* Basic C++ support */
extern "C" {
#endif

/* Declaration modifiers for DLL support (MSC et al) */
#include "declspec.h"

/* Prototypes of all modules in the GMT ${L_TAG} library */
EOF
gawk '{printf "EXTERN_MSC int GMT_%s (void *API, int mode, void *args);\n", $2;}' /tmp/$LIB.txt >> ${FILE_GMT_MODULE_H}
cat << EOF >> ${FILE_GMT_MODULE_H}

/* Pretty print all modules in the GMT ${L_TAG} library and their purposes */
EXTERN_MSC void gmt_${L_TAG}_module_show_all (void *API);
/* List all modern modules in the GMT ${L_TAG} library to stdout */
EXTERN_MSC void gmt_${L_TAG}_module_list_all (void *API);
/* List all classic modules in the GMT ${L_TAG} library to stdout */
EXTERN_MSC void gmt_${L_TAG}_module_classic_all (void *API);
/* Function called by GMT_Encode_Options so developers can get information about a module */
EXTERN_MSC const char * gmt_${L_TAG}_module_keys (void *API, char *candidate);
/* Function returns name of group that module belongs to (core, spotter, etc.) */
EXTERN_MSC const char * gmt_${L_TAG}_module_group (void *API, char *candidate);

#ifdef __cplusplus
}
#endif

#endif /* !GMT_${U_TAG}_MODULE_H */
EOF

#
# Generate FILE_GMT_MODULE_C
#

cat << EOF > ${FILE_GMT_MODULE_C}
/*
 * Copyright (c) 2012-${COPY_YEAR} by the GMT Team (https://www.generic-mapping-tools.org/team.html)
 * See LICENSE.TXT file for copying and redistribution conditions.
 */

/* gmt_${L_TAG}_module.c populates the external array of GMT ${L_TAG} with
 * module parameters such as name, group, purpose and keys strings.
 * This file also contains the following convenience functions to
 * display all module purposes or just list their names:
 *
 *   void gmt_${L_TAG}_module_show_all (struct GMTAPI_CTRL *API);
 *   void gmt_${L_TAG}_module_list_all (void *API);
 *
 * These functions may be called by gmt --help and gmt --show-modules
 *
 * Developers of external APIs for accessing GMT modules will use this
 * function indirectly via GMT_Encode_Options to retrieve option keys
 * needed for module arg processing:
 *
 *   char * gmt_${L_TAG}_module_keys (void *API, const char *module);
 *
 * DO NOT edit this file directly! Regenerate the file by running
 * 	gmt_make_module_src.sh ${L_TAG}
 */
EOF
if [ "$U_TAG" = "CORE" ]; then
	cat << EOF >> ${FILE_GMT_MODULE_C}
#include "gmt_dev.h"
#ifndef BUILD_SHARED_LIBS
#include "${FILE_GMT_MODULE_H}"
#endif

EOF
else
	cat << EOF >> ${FILE_GMT_MODULE_C}
#include "gmt.h"
#include "gmt_notposix.h"       /* Non-POSIX extensions */
#define gmt_M_unused(x) (void)(x)
#define GMT_LEN256 256
#include "gmt_supplements_module.h"
#include <string.h>
EOF
fi
cat << EOF >> ${FILE_GMT_MODULE_C}

/* Sorted array with information for all GMT ${L_TAG} modules */

/* name, library, and purpose for each module */
struct Gmt_moduleinfo {
	const char *mname;            /* Program (modern) name */
	const char *cname;            /* Program (classic) name */
	const char *component;        /* Component (core, supplement, custom) */
	const char *purpose;          /* Program purpose */
	const char *keys;             /* Program option info for external APIs */
EOF
if [ "$U_TAG" = "CORE" ]; then
	cat << EOF >> ${FILE_GMT_MODULE_C}
#ifndef BUILD_SHARED_LIBS
	/* gmt module function pointer: */
	int (*p_func)(void*, int, void*);
#endif
EOF
fi
cat << EOF >> ${FILE_GMT_MODULE_C}
};
EOF

if [ "$U_TAG" = "CORE" ]; then
	cat << EOF >> ${FILE_GMT_MODULE_C}

static struct Gmt_moduleinfo g_${L_TAG}_module[] = {
#ifdef BUILD_SHARED_LIBS
EOF

# $1 = mname, $2 = cname, $3 = ${L_TAG}, $4 = tab, $5 = purpose, $6 = tab, $7 = keys
gawk '
	BEGIN {
		FS = "\t";
	}
	{ printf "\t{\"%s\", \"%s\", \"%s\", %s, %s},\n", $1, $2, $3, $5, $7;
}' /tmp/$LIB.txt >> ${FILE_GMT_MODULE_C}

cat << EOF >> ${FILE_GMT_MODULE_C}
	{NULL, NULL, NULL, NULL, NULL} /* last element == NULL detects end of array */
#else
EOF
# $1 = mname, $2 = cname, $3 = core/supplement, $4 = Api_mode, $5 = purpose, $6 = tab, $7 = keys
gawk '
	BEGIN {
		FS = "\t";
	}
	!/^[ \t]*#/ {
		printf "\t{\"%s\", \"%s\", \"%s\", %s, %s, &GMT_%s},\n", $1, $2, $3, $5, $7, $1;
	}' /tmp/$LIB.txt >> ${FILE_GMT_MODULE_C}

cat << EOF >> ${FILE_GMT_MODULE_C}
	{NULL, NULL, NULL, NULL, NULL, NULL} /* last element == NULL detects end of array */
#endif
};
EOF
else
	cat << EOF >> ${FILE_GMT_MODULE_C}

static struct Gmt_moduleinfo g_${L_TAG}_module[] = {
EOF

# $1 = mname, $2 = cname, $3 = ${L_TAG}, $4 = tab, $5 = purpose, $6 = tab, $7 = keys
gawk '
	BEGIN {
		FS = "\t";
	}
	{ printf "\t{\"%s\", \"%s\", \"%s\", %s, %s},\n", $1, $2, $3, $5, $7;
}' /tmp/$LIB.txt >> ${FILE_GMT_MODULE_C}

cat << EOF >> ${FILE_GMT_MODULE_C}
	{NULL, NULL, NULL, NULL, NULL} /* last element == NULL detects end of array */
};
EOF
fi
if [ "$U_TAG" = "CORE" ]; then
	cat << EOF >> ${FILE_GMT_MODULE_C}

/* Function to exclude some special core modules from being reported by gmt --help|show-modules */
GMT_LOCAL int skip_this_module (const char *name) {
	if (!strncmp (name, "gmtread", 7U)) return 1;	/* Skip the gmtread module */
	if (!strncmp (name, "gmtwrite", 8U)) return 1;	/* Skip the gmtwrite module */
	return 0;	/* Display this one */
}

/* Function to exclude modern mode modules from being reported by gmt --show-classic */
GMT_LOCAL int skip_modern_module (const char *name) {
	if (!strncmp (name, "subplot", 7U)) return 1;	/* Skip the subplot module */
	if (!strncmp (name, "figure", 6U)) return 1;	/* Skip the figure module */
	if (!strncmp (name, "begin", 5U)) return 1;		/* Skip the begin module */
	if (!strncmp (name, "clear", 5U)) return 1;		/* Skip the clear module */
	if (!strncmp (name, "inset", 5U)) return 1;		/* Skip the inset module */
	if (!strncmp (name, "movie", 5U)) return 1;		/* Skip the movie module */
	if (!strncmp (name, "docs", 4U)) return 1;		/* Skip the docs module */
	if (!strncmp (name, "end", 3U)) return 1;		/* Skip the end module */
	return 0;	/* Display this one */
}
EOF
fi
cat << EOF >> ${FILE_GMT_MODULE_C}

/* Pretty print all GMT ${L_TAG} module names and their purposes for gmt --help */
void gmt_${L_TAG}_module_show_all (void *V_API) {
	unsigned int module_id = 0;
	char message[GMT_LEN256];
EOF
if [ "$U_TAG" = "CORE" ]; then
	cat << EOF >> ${FILE_GMT_MODULE_C}
	struct GMTAPI_CTRL *API = gmt_get_api_ptr (V_API);
EOF
fi
cat << EOF >> ${FILE_GMT_MODULE_C}
	GMT_Message (V_API, GMT_TIME_NONE, "\n===  $LIB_STRING  ===\n");
	while (g_${L_TAG}_module[module_id].cname != NULL) {
		if (module_id == 0 || strcmp (g_${L_TAG}_module[module_id-1].component, g_${L_TAG}_module[module_id].component)) {
			/* Start of new supplemental group */
			snprintf (message, GMT_LEN256, "\nModule name:     Purpose of %s module:\n", g_${L_TAG}_module[module_id].component);
			GMT_Message (V_API, GMT_TIME_NONE, message);
			GMT_Message (V_API, GMT_TIME_NONE, "----------------------------------------------------------------\n");
		}
EOF
if [ "$U_TAG" = "CORE" ]; then
		cat << EOF >> ${FILE_GMT_MODULE_C}
		if (API->external || !skip_this_module (g_${L_TAG}_module[module_id].cname)) {
			snprintf (message, GMT_LEN256, "%-16s %s\n",
				g_${L_TAG}_module[module_id].mname, g_${L_TAG}_module[module_id].purpose);
				GMT_Message (V_API, GMT_TIME_NONE, message);
		}
EOF
else
		cat << EOF >> ${FILE_GMT_MODULE_C}
		snprintf (message, GMT_LEN256, "%-16s %s\n",
			g_${L_TAG}_module[module_id].mname, g_${L_TAG}_module[module_id].purpose);
			GMT_Message (V_API, GMT_TIME_NONE, message);
EOF
fi
cat << EOF >> ${FILE_GMT_MODULE_C}
		++module_id;
	}
}

EOF

cat << EOF >> ${FILE_GMT_MODULE_C}
/* Produce single list on stdout of all GMT ${L_TAG} module names for gmt --show-modules */
void gmt_${L_TAG}_module_list_all (void *V_API) {
	unsigned int module_id = 0;
EOF
if [ "$U_TAG" = "CORE" ]; then
	cat << EOF >> ${FILE_GMT_MODULE_C}
	struct GMTAPI_CTRL *API = gmt_get_api_ptr (V_API);
EOF
else
	cat << EOF >> ${FILE_GMT_MODULE_C}
	gmt_M_unused(V_API);
EOF
fi
cat << EOF >> ${FILE_GMT_MODULE_C}
	while (g_${L_TAG}_module[module_id].cname != NULL) {
EOF
if [ "$U_TAG" = "CORE" ]; then
		cat << EOF >> ${FILE_GMT_MODULE_C}
		if (API->external || !skip_this_module (g_${L_TAG}_module[module_id].cname))
			printf ("%s\n", g_${L_TAG}_module[module_id].mname);
EOF
else
		cat << EOF >> ${FILE_GMT_MODULE_C}
		printf ("%s\n", g_${L_TAG}_module[module_id].mname);
EOF
fi
cat << EOF >> ${FILE_GMT_MODULE_C}
		++module_id;
	}
}

/* Produce single list on stdout of all GMT ${L_TAG} module names for gmt --show-classic [i.e., classic mode names] */
void gmt_${L_TAG}_module_classic_all (void *V_API) {
	unsigned int module_id = 0;
EOF
if [ "$U_TAG" = "CORE" ]; then
	cat << EOF >> ${FILE_GMT_MODULE_C}
	struct GMTAPI_CTRL *API = gmt_get_api_ptr (V_API);
EOF
else
	cat << EOF >> ${FILE_GMT_MODULE_C}
	gmt_M_unused(V_API);
EOF
fi
cat << EOF >> ${FILE_GMT_MODULE_C}
	while (g_${L_TAG}_module[module_id].cname != NULL) {
EOF
if [ "$U_TAG" = "CORE" ]; then
		cat << EOF >> ${FILE_GMT_MODULE_C}
		if (API->external || !(skip_this_module (g_${L_TAG}_module[module_id].cname) || skip_modern_module (g_${L_TAG}_module[module_id].cname)))
			printf ("%s\n", g_${L_TAG}_module[module_id].cname);
EOF
else
		cat << EOF >> ${FILE_GMT_MODULE_C}
		printf ("%s\n", g_${L_TAG}_module[module_id].cname);
EOF
fi
cat << EOF >> ${FILE_GMT_MODULE_C}
		++module_id;
	}
}

/* Lookup module id by name, return option keys pointer (for external API developers) */
const char *gmt_${L_TAG}_module_keys (void *API, char *candidate) {
	int module_id = 0;
	gmt_M_unused(API);

	/* Match actual_name against g_module[module_id].cname */
	while (g_${L_TAG}_module[module_id].cname != NULL &&
	       strcmp (candidate, g_${L_TAG}_module[module_id].cname))
		++module_id;

	/* Return Module keys or NULL */
	return (g_${L_TAG}_module[module_id].keys);
}

/* Lookup module id by name, return group char name (for external API developers) */
const char *gmt_${L_TAG}_module_group (void *API, char *candidate) {
	int module_id = 0;
	gmt_M_unused(API);

	/* Match actual_name against g_module[module_id].cname */
	while (g_${L_TAG}_module[module_id].cname != NULL &&
	       strcmp (candidate, g_${L_TAG}_module[module_id].cname))
		++module_id;

	/* Return Module keys or NULL */
	return (g_${L_TAG}_module[module_id].component);
}
EOF

if [ "$U_TAG" = "CORE" ]; then
	cat << EOF >> ${FILE_GMT_MODULE_C}

#ifndef BUILD_SHARED_LIBS
/* Lookup static module id by name, return function pointer */
void *gmt_${L_TAG}_module_lookup (void *API, const char *candidate) {
	int module_id = 0;
	size_t len = strlen (candidate);
	gmt_M_unused(API);

	if (len < 4) return NULL;	/* All candidates should start with GMT_ */
	/* Match actual_name against g_module[module_id].cname */
	while (g_${L_TAG}_module[module_id].cname != NULL &&
	       strcmp (&candidate[4], g_${L_TAG}_module[module_id].cname))
		++module_id;

	/* Return Module function or NULL */
	return (g_${L_TAG}_module[module_id].p_func);
}
#endif
EOF
fi
rm -f /tmp/$LIB.txt
exit 0
