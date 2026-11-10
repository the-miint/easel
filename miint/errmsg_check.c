/* errmsg_check: driver for the error-message check in miint/check.sh.
 *
 * Usage: errmsg_check ppid|fail|exception|fatal
 *   ppid       print getppid(), so check.sh can confirm it set up a PID-1 parent
 *   fail       esl_fail() into an error buffer, then print the buffer on stdout
 *   exception  esl_exception() with no handler: message on stderr, then abort()
 *   fatal      esl_fatal(): message on stderr, then exit(1)
 * Each message contains MARK and the mode name, which check.sh looks for.
 *
 * Why: upstream Easel treats getppid() == 1 as "running as a daemon"
 * and sends these messages to syslog instead. A process whose parent
 * is PID 1 is usually not a daemon (a container's entrypoint, a
 * process under `unshare`, an orphan), and under WebAssembly getppid()
 * is always 1. The message was lost: esl_fail() left the caller's
 * buffer unset, and wasm's syslog aborts the module.
 */
#include <esl_config.h>

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "easel.h"

#define MARK "miint-errmsg-check"

int
main(int argc, char **argv)
{
  char errbuf[eslERRBUFSIZE] = "";

  if (argc == 2 && strcmp(argv[1], "ppid") == 0)
    {
      printf("%d\n", (int) getppid());
      return 0;
    }
  if (argc == 2 && strcmp(argv[1], "fail") == 0)
    {
      esl_fail(errbuf, "%s %s", MARK, "fail");
      printf("%s\n", errbuf);
      return 0;
    }
  if (argc == 2 && strcmp(argv[1], "exception") == 0)
    esl_exception(eslEINVAL, FALSE, __FILE__, __LINE__, "%s %s", MARK, "exception");
  if (argc == 2 && strcmp(argv[1], "fatal") == 0)
    esl_fatal("%s %s", MARK, "fatal");

  fprintf(stderr, "usage: %s ppid|fail|exception|fatal\n", argv[0]);
  return 2;
}
