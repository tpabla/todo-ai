import time
import random

import time
import random


import time
import random
import sys


def print_ascii_art():
    art_options = [
        """
    ╔═══════════════════════════════════╗
    ║           HELLO WORLD!            ║
    ║                                   ║
    ║      🚀    ✨    🌟    💫        ║
    ║                                   ║
    ║   Welcome to the Code Universe!   ║
    ╚═══════════════════════════════════╝
        """,
        """
         _   _      _ _         __        __         _     _ _
        | | | | ___| | | ___    \ \      / /__  _ __| | __| | |
        | |_| |/ _ \ | |/ _ \    \ \ /\ / / _ \| '__| |/ _` | |
        |  _  |  __/ | | (_) |    \ V  V / (_) | |  | | (_| |_|
        |_| |_|\___|_|_|\___/      \_/\_/ \___/|_|  |_|\__,_(_)

        """,
        """
    ░█████╗░░█████╗░██████╗░███████╗  ██╗░░░░░██╗███████╗███████╗
    ██╔══██╗██╔══██╗██╔══██╗██╔════╝  ██║░░░░░██║██╔════╝██╔════╝
    ██║░░╚═╝██║░░██║██║░░██║█████╗░░  ██║░░░░░██║█████╗░░█████╗░░
    ██║░░██╗██║░░██║██║░░██║██╔══╝░░  ██║░░░░░██║██╔══╝░░██╔══╝░░
    ╚█████╔╝╚█████╔╝██████╔╝███████╗  ███████╗██║██║░░░░░███████╗
    ░╚════╝░░╚════╝░╚═════╝░╚══════╝  ╚══════╝╚═╝╚═╝░░░░░╚══════╝
        """
    ]
    return random.choice(art_options)


def animate_text(text, delay=0.05):
    """Type out text with animation effect"""
    for char in text:
        print(char, end='', flush=True)
        time.sleep(delay)
    print()


def loading_animation():
    """Fun loading animation"""
    frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
    for i in range(20):
        print(f'\rLoading awesome content {
              frames[i % len(frames)]}', end='', flush=True)
        time.sleep(0.1)
    print('\r' + ' ' * 30 + '\r', end='')


def main():
    try:
        # Clear screen effect
        print('\n' * 3)

        # Fun loading animation
        loading_animation()

        # Show ASCII art
        print(print_ascii_art())

        # Animated welcome messages
        messages = [
            "🚀 Blast off into the coding universe! 🌌",
            "✨ Where magic meets logic! ✨",
            "🌟 Code like the star you are! 🌟",
            "💻 Hello from the digital realm! 🌐",
            "🎉 Welcome to the fun zone! 🎊"
        ]

        selected_message = random.choice(messages)
        animate_text(f"\n{selected_message}")

        # Fun interactive element
        time.sleep(1)
        print("\n" + "="*50)
        animate_text("🎮 Interactive Mode Activated! 🎮")
        print("="*50)

        # Random fun facts about coding
        fun_facts = [
            "💡 Fun Fact: The first computer bug was an actual bug (moth) found in 1947!",
            "💡 Fun Fact: Python is named after Monty Python's Flying Circus!",
            "💡 Fun Fact: The first programmer was Ada Lovelace in 1843!",
            "💡 Fun Fact: 'Hello, World!' was first used in 1972!"
        ]

        time.sleep(1)
        animate_text(random.choice(fun_facts))

        # Interactive countdown
        print("\n🚪 Starting interactive session in:")
        for i in range(3, 0, -1):
            print(f"   {i}... 🕐")
            time.sleep(0.8)

        animate_text("🎉 Ready! Press Ctrl+C to exit anytime! 🎉")

        # Keep the program running with occasional fun messages
        counter = 0
        while True:
            time.sleep(3)
            counter += 1
            if counter % 5 == 0:
                emoji_sequence = ['🌟', '✨', '💫', '⭐', '🌠']
                print(f"\n{random.choice(emoji_sequence)} Still here? You're awesome! Keep coding! {
                      random.choice(emoji_sequence)}")

    except KeyboardInterrupt:
        print("\n\n" + "="*40)
        animate_text("👋 Thanks for visiting! Keep coding! 🚀")
        print("="*40)
        print("\n🌟 See you in the code universe! 🌟\n")
        sys.exit(0)


if __name__ == "__main__":
    main()


def main():
    messages = [
        "🚀 Hello, world! 🌍",
        "✨ Welcome to the universe of code! ✨",
        "🌟 Hey there, code lover! 🌟",
    ]
    print(random.choice(messages))
    time.sleep(1)
    print("Press Ctrl+C to exit... 🚪")
    print("Hello, world!")


if __name__ == "__main__":
    main()
