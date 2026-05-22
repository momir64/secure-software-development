# [DOM-based open redirection](https://portswigger.net/web-security/dom-based/open-redirection/lab-dom-open-redirection)

## Steps

- The task is about finding the redirection vulnerability so I went to page source and searched for redirect or location.href. Didn't find anything so i decided to go on one of the blogs on the page

- When running search on the blog post I found this for location.
  
```
<div class="is-linkback">
    <a href='#' onclick='returnUrl = /url=(https?:\/\/.+)/.exec(location); location.href = returnUrl ? returnUrl[1] : "/"'>Back to Blog</a>
</div>
```

What this does is, when clicked it makes a returnUrl value. It calculates it by running exec with a regex - this searches for text within the passed string that matches the regex pattern. The location obj is converted to string autoatically. Then it sets the webpage url to be the returnUrl value. 

- So what I need to do is place my exploitative url in location to be read by this. I entered 
https://0ad100c6048ca8638178616c008600d6.web-security-academy.net/post?postId=4&url=https://exploit-0ad000910477a88881a9606801b5001e.exploit-server.net

Pressed enter and the lab was solved. 

![screenshot](img/04/01.png)
