/*
 * src_convention_check.c is used to check if we are following our own naming
 * convention for functions in the API (GMT_*), the core library (gmt_*),
 * the inter-file functions (gmtlib_*) or the in-file static function
 * (gmtfile_*).  We also try to determine how many files a function is called
 * in to look for candidate for static functions.
 * Options:
 *			-e Only list the external funtions and skip static ones
 *			-f Only list functions and not where they are called
 *
 * Paul Wessel, April 2020
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libgen.h>

#define NFILES 500
#define NFUNCS 10000

struct FUNCTION {
	char name[64];	/* Name of function */
	char file[64];	/* Name if file it is declared in */
	int api;		/* 1 if declared extern in gmt.h */
	int declared_dev;		/* 1 if declared extern in gmt_prototypes.h */
	int declared_lib;		/* 1 if declared extern in gmt_internals.h */
	int declared_local;		/* True if function declared static */
	int determined_dev;		/* 1 if called by a module */
	int determined_lib;		/* 1 if called in gmt_*.c */
	int determined_local;	/* True if function only appears in one file */
	unsigned int n_files;	/* How many files referenced */
	unsigned int n_calls;	/* How many times referenced */
	char *in;
};

int find_function (struct FUNCTION *F, int N, char *name) {
	int k;
	for (k = 0; k < N; k++)
		if (!strcmp (F[k].name, name)) return k;
	return -1;
}

static int compare_n (const void *v1, const void *v2) {
	const struct FUNCTION *F1 = v1, *F2 = v2;
	if (F1->n_files < F2->n_files) return +1;
	if (F1->n_calls > F2->n_files) return -1;
	if (F1->n_files < F2->n_calls) return +1;
	if (F1->n_calls > F2->n_calls) return -1;
	return (0);
}

static char *modules[] = {
#include "/tmp/gmt/modules.h"
	NULL
};

static char *API[] = {
#include "/tmp/gmt/api.h"
	NULL
};

static char *libdev[] = {
#include "/tmp/gmt/prototypes.h"
	NULL
};

static char *libint[] = {
#include "/tmp/gmt/internals.h"
	NULL
};

static int is_recognized (char *name, char *list[]) {
	int k = 0;
	while (list[k]) {
		if (strstr (name, list[k]))
			return 1;
		else k++;
	}
	return 0;
}

static void get_contraction (char *name, char *prefix) {
	unsigned k, j;
	for (k = j = 0; name[k] != '.'; k++)
		if (name[k] != '_') prefix[j++] = name[k];
	prefix[j] = '\0';
}

int main (int argc, char **argv) {
	int k, f, w, s, n, is_static, err, n_funcs = 0, comment = 0, brief = 0, ext = 0, log = 1, verbose = 0, warn_only = 0;
	int set_dev, set_lib;
	size_t L;
	char line[512] = {""}, prefix[64] = {""};
	char word[6][64], type[3] = {'S', 'D', 'L'}, *p, message[128] = {""};
	char *err_msg[4] = {"", "Name error, should be gmt_*", "Name error, should be gmtlib_*", "Name error, should be file_*"};
	struct FUNCTION F[NFUNCS];
	FILE *fp, *out = stdout;

	if (argc == 1) {
		fprintf (stderr, "usage: src_convention_check [-e] [-f] [-o] *.c > log\n");
		fprintf (stderr, "	-e Only list external functions [all]\n");
		fprintf (stderr, "	-f Only list function stats and not where called [full log]\n");
		fprintf (stderr, "	-o Write main results to stdout [/tmp/gmt/gmt/scan.txt\n");
		fprintf (stderr, "	-v Extra verbose output [minimal verbosity]\n");
		fprintf (stderr, "	-w Only write lines with warnings of wrong naming]\n");
		exit (1);
	}
	fprintf (stderr, "1. Scanning all codes for function declarations\n");
	for (k = 1; k < argc; k++) {	/* For each input file */
		if (strcmp (argv[k], "-f") == 0) {	/* Only list functions and not where called */
			brief = 1;
			continue;
		}
		if (strcmp (argv[k], "-e") == 0) {	/* Only list external functions and not static */
			ext = 1;
			continue;
		}
		if (strcmp (argv[k], "-o") == 0) {	/* Write to stdout */
			log = 0;
			continue;
		}
		if (strcmp (argv[k], "-v") == 0) {	/* Extra verbos */
			verbose = 1;
			continue;
		}
		if (strcmp (argv[k], "-w") == 0) {	/* Warnings only e*/
			warn_only = 1;
			continue;
		}
		if ((fp = fopen (argv[k], "r")) == NULL) continue;
		if (verbose) fprintf (stderr, "\tScanning %s\n", argv[k]);
		comment = 0;
		while (fgets (line, 512, fp)) {
			if (!comment && strstr (line, "/*") && strstr (line, "*/") == NULL)	/* Start of multi-line comment */
				comment = 1;
			else if (comment && strstr (line, "*/")) {	/* End of multi-line comment with this line */
				comment = 0;
				continue;
			}
			if (comment) continue;
			if (strchr (" \t#/{", line[0])) continue;
			if (line[1] == '*') continue;	/* Comment */
			if (strchr (line, '(') == NULL) continue;
			if (!strncmp (line, "EXTERN", 6U)) continue;
			if (!strncmp (line, "extern", 6U)) continue;
			if (strstr (line, "typedef")) continue;
			n = sscanf (line, "%s %s %s %s %s", word[0], word[1], word[2], word[3], word[4]);
			if (n < 2) continue;
			w = is_static = 0;
			if (!strcmp (word[w], "if") || !strcmp (word[w], "for") || !strcmp (word[w], "while") || !strcmp (word[w], "else")) continue;
			if (strchr (word[0], ':')) continue;	/* goto label */
			if (strchr (word[0], '(')) continue;	/* function call */
			if (!strcmp (word[w], "GMT_LOCAL") || !strcmp (word[w], "static")) {
				w = is_static = 1;
			}
			if (ext && is_static) continue;	/* Only list external functions since -e is set */
			if (!strncmp (word[w], "inline", 6U))
				w++;	/* Skip inline  */
			if (!strncmp (word[w], "const", 5U))
				w++;	/* Skip inline  */
			if (!strncmp (word[w], "struct", 6U)) {	/* Skip "struct NAME" */
				w += 2;
				if (strchr (word[w], '{')) continue;	/* Was a structure definition */
			}
			else if (!strncmp (word[w], "unsigned", 8U) || !strncmp (word[w], "signed", 6U))
				w += 2;	/* Skip "unsigned short" */
			else	/* skip "double", etc. */
				w++;
			if (w >= n) continue;
			if (!strcmp (word[w], "*") || !strcmp (word[w], "**"))
				w++;	/* Skip a lonely * */
			if (w >= n) continue;
			s = (word[w][0] == '*') ? 1 : 0;	/* Skip leading * if there is no space */
			if (strchr (&word[w][s], '[')) continue;	/* Got some array */
			L = strlen (word[w]);
			if (L > 5 && strncmp (&word[w][s], "GMT_", 4U) == 0) continue;	/* Skip GMT API functions */
			if (L > 5 && strncmp (&word[w][s], "PSL_", 4U) == 0) continue;	/* Skip PSL functions */
			if (word[w][L-1] == '_') continue;	/* Skip FORTRAN wrappers */
			if ((p = strchr (word[w], '('))) p[0] = '\0';	/* Change functionname(args) to functionname */
			if (strcmp (&word[w][s], "main") == 0) continue;	/* Skip main functions in modules */
			if (strcmp (&word[w][s], "{") == 0)
				p = NULL;
			if ((f = find_function (F, n_funcs, &word[w][s])) == -1) {
				f = n_funcs++;	/* Add one more */
				strncpy (F[f].name, &word[w][s], 63);
				strncpy (F[f].file, argv[k], 63);
				if (is_recognized (argv[k], API))
					F[f].api = 1;
				else if (is_recognized (argv[k], libdev))
					F[f].declared_dev = 1;
				else if (is_recognized (argv[k], libint))
					F[f].declared_dev = 1;
				F[f].declared_local = is_static;
				F[f].in = calloc (NFILES, 1U);
			}
			if (n_funcs == NFUNCS) {
				fprintf (stderr, "Out of function space\n");
				exit (-1);
			}
		}
		fclose (fp);
	}
	/* Look for function calls */
	fprintf (stderr, "2. Scanning all codes for function calls\n");
	for (k = 1; k < argc; k++) {	/* For each input file */
		if ((fp = fopen (argv[k], "r")) == NULL) continue;
		if (verbose) fprintf (stderr, "\tScanning %s\n", argv[k]);
		set_dev = is_recognized (argv[k], modules);	/* Called in a module */
		set_lib = (strstr (argv[k], "gmt_") != NULL || strstr (argv[k], "common_") != NULL);	/* Called in a library file */
		while (fgets (line, 512, fp)) {
			if (line[0] == '/' || line[1] == '*') continue;	/* Comment */
			if (strchr (" \t", line[0]) == NULL) continue;
			if (strchr (line, '[')) continue;	/* Got some array */
			if (strchr (line, '(') == NULL) continue;	/* Not a function call */
			for (f = 0; f < n_funcs; f++) {
				L = strlen (F[f].name);
				if ((p = strstr (line, F[f].name)) && strlen (p) > L && (p[L] == '(' || p[L] == ' ')) {	/* Found a call to this function */
					F[f].in[k] = 1;
					F[f].n_calls++ ;
					if (set_dev) F[f].determined_dev = 1;	/* Called in a module */
					if (set_lib) F[f].determined_lib = 1;	/* Called in a library function */
				}
			}
		}
	}
	for (f = 0; f < n_funcs; f++) {
		for (k = 1; k < argc; k++)	/* For each input file */
			if (F[f].in[k]) F[f].n_files++;
	}
	qsort (F, n_funcs, sizeof (struct FUNCTION), compare_n);

	fprintf (stderr, "Write the report\n");
	/* Report */
	if (log) out = fopen ("/tmp/gmt/scan.txt", "w");
	fprintf (out, "NFILES  FUNCTION                                    NCALLS TYPE DECLARED-IN\n");
	for (f = 0; f < n_funcs; f++) {
		err = 0;
		p = basename (F[f].file);
		L = strlen (p);
		k = (F[f].declared_local) ? 0 : ((F[f].declared_dev) ? 1 : 2);
		if (F[f].declared_local) {
			if (strncmp (F[f].name, p, L-2)) err = 3;
		}
		else if (F[f].declared_dev) {
			if (strncmp (F[f].name, "gmt_", 4U)) err = 1;
		}
		else if (F[f].declared_lib) {
			if (strncmp (F[f].name, "gmtlib_", 7U)) err = 2;
		}
		if (err == 3) {
			if (F[f].n_files > 1)
				strcpy (message, err_msg[err]);
			else {
				get_contraction (p, prefix);
				sprintf (message, "Name error, should be %s_*", prefix);
			}
		}
		else
			strcpy (message, err_msg[err]);
		if (!warn_only || err) {
			fprintf (out, "%4d\t%-40s\t%4d\t%c\t%s\t%s\n", F[f].n_files, F[f].name, F[f].n_calls, type[k], F[f].file, message);
			if (brief) {	/* Done with this, free memory */
				free ((void *)F[f].in);
				continue;
			}
			for (k = 1; k < argc; k++)	/* For each input file, report each incident */
				if (F[f].in[k] && strcmp (argv[k], F[f].file)) fprintf (out, "\t\t%s\n", argv[k]);
		}
		free ((void *)F[f].in);
	}
	if (log) fclose (out);
}