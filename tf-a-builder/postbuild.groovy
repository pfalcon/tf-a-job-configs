import hudson.model.*

def getUpstreamRoot(cause) {
    causes = cause.getUpstreamCauses()
    if (causes.size() > 0) {
        if (causes[0] instanceof hudson.model.Cause.UpstreamCause) {
            return getUpstreamRoot(causes[0])
        }
    }
    return cause
}

// Add a LAVA job link to the description
def matcher = manager.getLogMatcher("TEST JOB URL: (?<url>.*?) TEST JOB ID: (?<jobid>\\d+)")
if (matcher?.matches()) {
    def testJobId = matcher.group('jobid')
    def testJobUrl = matcher.group('url')
    def testDescription = "&nbsp;Test Job Id: <a href='${testJobUrl}'>${testJobId}</a>"

    def rootUrl = manager.hudson.getRootUrl()
    def lavaLogUrl = "${rootUrl}${manager.build.url}artifact/lava.log"
    def lavaDescription = "<br >&nbsp;LAVA log: <a href='${lavaLogUrl}'>lava.log</a>"

    def causes = manager.build.getAction(hudson.model.CauseAction.class).getCauses()
    if (causes[0] instanceof hudson.model.Cause.UpstreamCause) {
        def rootCause = getUpstreamRoot(causes[0])
        def upstreamBuild = rootCause.upstreamBuild
        def upstreamProject = rootCause.upstreamProject
        def jobName = upstreamProject
        def jobConfiguration = upstreamProject
        def jobUrl = "${rootUrl}job/${upstreamProject}/${upstreamBuild}"
        def jobDescription = "<br>&nbsp;Build <a href='${jobUrl}'>${upstreamProject} #${upstreamBuild}</a>"

        manager.build.setDescription(testDescription + lavaDescription + jobDescription)
    }

    // Verify LAVA jobs results, all tests must pass, otherwise turn build into UNSTABLE
    def testMatcher = manager.getLogMatcher("LAVA JOB RESULT: (?<result>\\d+)")
    if (testMatcher?.matches()) {
        def testJobSuiteResult = testMatcher.group('result')
        // result = 1 means lava job fails
        if (testJobSuiteResult == "1") {
            manager.buildFailure()
        }
    }
}
