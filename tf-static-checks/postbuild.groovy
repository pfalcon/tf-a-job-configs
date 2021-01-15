import hudson.model.*

void log(msg) {
  manager.listener.logger.println(msg)
}

def findRealUrl(url) {
  def connection = url.openConnection()
  connection.followRedirects = false
  connection.requestMethod = "GET"
  connection.connect()
  if (connection.responseCode == 302) {
    if (connection.headerFields.'Location') {
      return findRealUrl(connection.headerFields.Location.first().toURL())
    } else {
      log('Failed to follow redirect')
    }
  }
  return url
}

def artifact = "trusted-firmware-a/static-checks.log"
def jobUrl = manager.hudson.getRootUrl() + "${manager.build.url}artifact/${artifact}"
def url = new URL(jobUrl)
def realUrl = findRealUrl(url)
def connection = realUrl.openConnection()
connection.requestMethod = "GET"
if (connection.responseCode == 200) {
  def summaryContent = connection.content.text
  def summary = manager.createSummary("clipboard.gif")
  def buildResult = manager.build.getResult()
  def summaryHeader = ""
  if (buildResult == Result.SUCCESS) {
    summaryHeader = '<h1 style="color:green;">All good! Here\'s a summary of the static checks warnings (if any):</h1>'
  } else {
    summaryHeader = '<h1 style="color:red;">Some static checks failed!</h1>'
  }
  summary.appendText(summaryHeader, false)
  summary.appendText("Here's a summary of the static check analysis :", false)
  summary.appendText("<pre>" + summaryContent + "</pre>", false)
} else {
  log("Connection response code: ${connection.responseCode}")
}
