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

def artifact = "report.html"
def jobUrl = manager.hudson.getRootUrl() + "${manager.build.url}artifact/${artifact}"
def url = new URL(jobUrl)
def realUrl = findRealUrl(url)
def connection = realUrl.openConnection()
connection.requestMethod = "GET"
if (connection.responseCode == 200) {
  def summaryContent = connection.content.text
  def summary = manager.createSummary("clipboard.gif")
  def buildResult = manager.build.getResult()
  summary.appendText(summaryContent, false)
} else {
  log("Connection response code: ${connection.responseCode}")
}
