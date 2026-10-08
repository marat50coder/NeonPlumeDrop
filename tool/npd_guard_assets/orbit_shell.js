(function(){
  var root = document.documentElement;
  if (!root || root.getAttribute('data-plume-ready') === '1') return;
  root.setAttribute('data-plume-ready','1');
  var glue = function(){ return Array.prototype.join.call(arguments, ''); };
  var pinInset = function(){
    var sides = ['top','right','bottom','left'];
    var i;
    for (i = 0; i < sides.length; i++) {
      var side = sides[i];
      root.style.setProperty(glue(String.fromCharCode(45,45),'safe','-area-','inset-',side), '0px');
      root.style.setProperty(glue(String.fromCharCode(45,45),'safe','-',side), '0px');
    }
    var short = ['sat','sar','sab','sal'];
    for (i = 0; i < short.length; i++) {
      root.style.setProperty(glue(String.fromCharCode(45,45), short[i]), '0px');
    }
  };
  var pinChrome = function(){
    root.style.overscrollBehavior = 'none';
    if (document.body) document.body.style.overscrollBehavior = 'none';
    root.style.webkitTapHighlightColor = 'rgba(0,0,0,0)';
    root.style.colorScheme = 'dark';
  };
  var pinFields = function(){
    var nodes = document.querySelectorAll('input,textarea,select,[contenteditable="true"]');
    var i;
    for (i = 0; i < nodes.length; i++) {
      nodes[i].style.fontSize = '16px';
    }
  };
  var wanted =
    'width=device-width, initial-scale=1, maximum-scale=1, ' +
    'minimum-scale=1, user-scalable' + '=no, viewport-fit=contain';
  var pinViewport = function(){
    var head = document.head || root;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta) return;
    meta = document.createElement('meta');
    meta.setAttribute('name', 'viewport');
    meta.setAttribute('content', wanted);
    head.appendChild(meta);
  };
  var railId = 'plume-orbit-rail';
  var pinRail = function(){
    var head = document.head || root;
    if (!head) return;
    var rail = document.getElementById(railId);
    if (!rail) {
      rail = document.createElement('style');
      rail.id = railId;
      head.appendChild(rail);
    }
    rail.textContent =
      '::-webkit-scrollbar{width:6px;height:6px}' +
      '::-webkit-scrollbar-thumb{background:rgba(61,239,255,.38);border-radius:4px}';
  };
  var kbUp = function(){
    var vv = window.visualViewport;
    return !!vv && vv.height < window.innerHeight * 0.73;
  };
  var refresh = function(){
    if (kbUp()) return;
    pinInset();
    pinChrome();
    pinViewport();
    pinFields();
    pinRail();
  };
  var wrapHist = function(name){
    var orig = history[name];
    if (typeof orig !== 'function') return;
    history[name] = function(){
      var out = orig.apply(this, arguments);
      window.setTimeout(refresh, 80);
      return out;
    };
  };
  wrapHist('pushState');
  wrapHist('replaceState');
  window.addEventListener('popstate', function(){
    window.setTimeout(refresh, 80);
  });
  var isField = function(node){
    return !!node && node.matches &&
      node.matches('input, textarea, select, [contenteditable="true"]');
  };
  document.addEventListener('focusin', function(ev){
    if (!isField(ev.target)) return;
    window.setTimeout(function(){
      var active = document.activeElement;
      if (isField(active)) active.scrollIntoView({block:'nearest'});
    }, 310);
  }, true);
  refresh();
  window.setTimeout(refresh, 240);
  window.setTimeout(refresh, 880);
  window.setInterval(refresh, 4100);
})();
