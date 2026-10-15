NAME = hyperx-control
APP_NAME = HyperXControl.app
SOURCES = Sources/*.swift
SWIFTC = swiftc
SWIFTFLAGS = -O -framework Cocoa -framework IOKit -framework CoreGraphics
INSTALL_DIR = /Applications
BIN_DIR = /usr/local/bin

.PHONY: all app install uninstall clean

all: $(NAME)

$(NAME): $(SOURCES)
	$(SWIFTC) $(SWIFTFLAGS) $(SOURCES) -o $(NAME)

app: $(NAME) AppIcon.icns
	mkdir -p $(APP_NAME)/Contents/MacOS
	mkdir -p $(APP_NAME)/Contents/Resources
	cp $(NAME) $(APP_NAME)/Contents/MacOS/$(NAME)
	cp Info.plist $(APP_NAME)/Contents/Info.plist
	cp AppIcon.icns $(APP_NAME)/Contents/Resources/AppIcon.icns

install: app
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(APP_NAME)
	cp -R $(APP_NAME) $(INSTALL_DIR)/
	mkdir -p $(BIN_DIR)
	cp $(NAME) $(BIN_DIR)/$(NAME)

uninstall:
	rm -rf $(INSTALL_DIR)/$(APP_NAME)
	rm -f $(BIN_DIR)/$(NAME)
	rm -f ~/Library/LaunchAgents/com.hyperx.control.plist

clean:
	rm -rf $(NAME) $(APP_NAME)
