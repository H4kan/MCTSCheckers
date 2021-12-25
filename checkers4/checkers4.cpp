

#include <iostream>
#include <stdlib.h>
#include <time.h>
#include <SFML/Graphics.hpp>
#include <SFML/Window.hpp>

#define WINDOW_WIDTH 800
#define WINDOW_HEIGHT 800
#define BOARD_SIZE 8
#define PAWN_ROWS 3
#define PAWN_SIZE 80

using namespace sf;
using namespace std;


void recolorFields(RectangleShape* fields)
{
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        bool isBlack = ((i / BOARD_SIZE) + (i % BOARD_SIZE)) % 2 == 0;
        if (isBlack)
            fields[i].setFillColor(Color::Black);
    }
}
 
void setupFields(RectangleShape* fieldShapes, int* fields)
{
    const Vector2f vecSize{ (float)(WINDOW_WIDTH / BOARD_SIZE), (float)(WINDOW_HEIGHT / BOARD_SIZE) };
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        fields[i] = -1;
        fieldShapes[i].setSize(vecSize);

        const Vector2f vecPos{ (float)((i % BOARD_SIZE) * WINDOW_WIDTH / BOARD_SIZE), 
            (float)(((BOARD_SIZE * BOARD_SIZE - 1 - i) / BOARD_SIZE) * WINDOW_HEIGHT / BOARD_SIZE) };
        fieldShapes[i].setPosition(vecPos);
    }
    recolorFields(fieldShapes);
}

void setPawnPosition(CircleShape& pawn, int row, int col)
{
    const Vector2f vecPos{ (float)(col * WINDOW_WIDTH / BOARD_SIZE + (WINDOW_WIDTH / BOARD_SIZE - PAWN_SIZE ) / 2), 
        (float)((BOARD_SIZE - 1 - row) * WINDOW_HEIGHT / BOARD_SIZE + (WINDOW_HEIGHT / BOARD_SIZE - PAWN_SIZE) / 2) };
    pawn.setPosition(vecPos);
}

void setupPawns(CircleShape* pawns, int* fields, int* rows, int* cols, bool* pawnHasKill, bool* isQueen)
{
    for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
    {
        pawns[i].setRadius(PAWN_SIZE / 2);
        pawns[i].setOutlineThickness(3);
        pawns[i].setOutlineColor(Color::Red);
        
        int row, col;
        if (i < PAWN_ROWS * BOARD_SIZE / 2)
        {
            pawns[i].setFillColor(Color::White);
            row = i / (BOARD_SIZE / 2);
            col = 2 * (i % (BOARD_SIZE / 2)) + ((i / (BOARD_SIZE / 2)) % 2);
            setPawnPosition(pawns[i], row, col);
            
        }
        else
        {
            row = BOARD_SIZE - 1 - ((i % (PAWN_ROWS * BOARD_SIZE / 2)) / (BOARD_SIZE / 2));
            col = 2 * (i % (BOARD_SIZE / 2)) + ((i / (BOARD_SIZE / 2)) % 2);
            pawns[i].setFillColor(Color::Black);
            setPawnPosition(pawns[i], row, col);
        }
        fields[row * BOARD_SIZE + col] = i;
        rows[i] = row;
        cols[i] = col;
        pawnHasKill[i] = false;
        isQueen[i] = false;
    }
}

bool isClickInShape(Shape& shape, Vector2f clickPos)
{
    Vector2f shapePosition = shape.getPosition();
    return clickPos.x >= shapePosition.x && clickPos.x <= shapePosition.x + shape.getLocalBounds().width
        && clickPos.y >= shapePosition.y && clickPos.y <= shapePosition.y + shape.getLocalBounds().height;
}

void clearAvailableFields(bool* available, int& numOfAvailable)
{ 
    numOfAvailable = 0;
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
        available[i] = false;
}

bool hasQueenKill(int* fields, int row, int col, int idx)
{
    int halfPawn = PAWN_ROWS * BOARD_SIZE / 2;

    for (int r = row + 1, c = col - 1; r < BOARD_SIZE - 1 && c > 0; r++, c--)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
        {
            if (fields[r * BOARD_SIZE + c] / halfPawn != idx / halfPawn
                && fields[(r + 1) * BOARD_SIZE + c - 1] < 0)
            {
                return true;
            }
            break;
        }
    }
    for (int r = row + 1, c = col + 1; r < BOARD_SIZE - 1 && c < BOARD_SIZE - 1; r++, c++)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
        {
            if (fields[r * BOARD_SIZE + c] / halfPawn != idx / halfPawn
                && fields[(r + 1) * BOARD_SIZE + c + 1] < 0)
            {
                return true;
            }
            break;
        }
    }
    for (int r = row - 1, c = col - 1; r > 0 && c > 0; r--, c--)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
        {
            if (fields[r * BOARD_SIZE + c] / halfPawn != idx / halfPawn
                && fields[(r - 1) * BOARD_SIZE + c - 1] < 0)
            {
                return true;
            }
            break;
        }
    }
    for (int r = row - 1, c = col + 1; r > 0 && c < BOARD_SIZE - 1; r--, c++)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
        {
            if (fields[r * BOARD_SIZE + c] / halfPawn != idx / halfPawn
                && fields[(r - 1) * BOARD_SIZE + c + 1] < 0)
            {
                return true;
            }
            break;
        }
    }
    return false;

}
bool hasKill(int* fields, int idx, int* rows, int* cols, bool isChainKill = false)
{
    int halfPawns = PAWN_ROWS * BOARD_SIZE / 2;
    // white
    if (idx < PAWN_ROWS * BOARD_SIZE / 2 || isChainKill)
    {
        if (rows[idx] >= 0 && rows[idx] < BOARD_SIZE - 2)
        {
            if (cols[idx] > 1)
            {
                if (fields[(rows[idx] + 1) * BOARD_SIZE + cols[idx] - 1] >= 0 &&
                    fields[(rows[idx] + 1) * BOARD_SIZE + cols[idx] - 1] / halfPawns != idx / halfPawns &&
                    fields[(rows[idx] + 2) * BOARD_SIZE + cols[idx] - 2] < 0)
                    return true;
            }
            if (cols[idx] >= 0 && cols[idx] < BOARD_SIZE - 2)
            {
                if (fields[(rows[idx] + 1) * BOARD_SIZE + cols[idx] + 1] >= 0 &&
                    fields[(rows[idx] + 1) * BOARD_SIZE + cols[idx] + 1] / halfPawns != idx / halfPawns &&
                    fields[(rows[idx] + 2) * BOARD_SIZE + cols[idx] + 2] < 0)
                    return true;
            }
        }
    }
    // black
    if (idx >= PAWN_ROWS * BOARD_SIZE / 2 || isChainKill)
    {
        if (rows[idx] > 1)
        {
            if (cols[idx] > 1)
            {
                if (fields[(rows[idx] - 1) * BOARD_SIZE + cols[idx] - 1] >= 0 &&
                    fields[(rows[idx] - 1) * BOARD_SIZE + cols[idx] - 1] / halfPawns != idx / halfPawns &&
                    fields[(rows[idx] - 2) * BOARD_SIZE + cols[idx] - 2] < 0)
                    return true;
            }
            if (cols[idx] >= 0 && cols[idx] < BOARD_SIZE - 2)
            {
                if (fields[(rows[idx] - 1) * BOARD_SIZE + cols[idx] + 1] >= 0 &&
                    fields[(rows[idx] - 1) * BOARD_SIZE + cols[idx] + 1] / halfPawns != idx / halfPawns &&
                    fields[(rows[idx] - 2) * BOARD_SIZE + cols[idx] + 2] < 0)
                    return true;
            }
        }
    }
    return false;
}

void setAvailableFields(int row, int col, bool isWhite, bool* available, int* fields, int& numOfAvailable)
{
    if (isWhite && row < BOARD_SIZE - 1)
    {
        if (col > 0 && fields[(row + 1) * BOARD_SIZE + col - 1] < 0)
        {
            available[(row + 1) * BOARD_SIZE + col - 1] = true;
            numOfAvailable++;
        }
        if (col < BOARD_SIZE - 1 && fields[(row + 1) * BOARD_SIZE + col + 1] < 0)
        {
            available[(row + 1) * BOARD_SIZE + col + 1] = true;
            numOfAvailable++;
        } 
    }
    else if (!isWhite && row > 0)
    {
        if (col > 0 && fields[(row - 1) * BOARD_SIZE + col - 1] < 0)
        {
            available[(row - 1) * BOARD_SIZE + col - 1] = true;
            numOfAvailable++;
        }
        if (col < BOARD_SIZE - 1 && fields[(row - 1) * BOARD_SIZE + col + 1] < 0)
        {
            available[(row - 1) * BOARD_SIZE + col + 1] = true;
            numOfAvailable++;
        }
    }
}

void setAvailableQueenFields(int row, int col, bool* available, int* fields, int& numOfAvailable)
{
    for (int r = row - 1, c = col - 1; r >= 0 && c >= 0; r--, c--)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;
        available[r * BOARD_SIZE + c] = true;
        numOfAvailable++;
    }
    for (int r = row + 1, c = col + 1; r < BOARD_SIZE && c < BOARD_SIZE; r++, c++)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;
        available[r * BOARD_SIZE + c] = true;
        numOfAvailable++;
    }
    for (int r = row - 1, c = col + 1; r >= 0 && c < BOARD_SIZE; r--, c++)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;
        available[r * BOARD_SIZE + c] = true;
        numOfAvailable++;
    }
    for (int r = row + 1, c = col - 1; r < BOARD_SIZE && c >= 0; r++, c--)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;
        available[r * BOARD_SIZE + c] = true;
        numOfAvailable++;
    }
}

void setAvailableKills(int* fields, int row, int col, int idx, bool isWhite, bool* available, int& numOfAvailable)
{
    int halfPawn = PAWN_ROWS * BOARD_SIZE / 2;
    if (isWhite)
    {
        if (col > 1 && row < BOARD_SIZE - 2 &&
            fields[(row + 2) * BOARD_SIZE + col - 2] < 0 &&
            fields[(row + 1) * BOARD_SIZE + col - 1] >= 0 &&
            fields[(row + 1) * BOARD_SIZE + col - 1] / halfPawn != idx / halfPawn)
        {
            available[(row + 2) * BOARD_SIZE + col - 2] = true;
            numOfAvailable++;
        }

        if (col < BOARD_SIZE - 2 && row < BOARD_SIZE - 2 &&
            fields[(row + 2) * BOARD_SIZE + col + 2] < 0 &&
            fields[(row + 1) * BOARD_SIZE + col + 1] >= 0 &&
            fields[(row + 1) * BOARD_SIZE + col + 1] / halfPawn != idx / halfPawn)
        {
            available[(row + 2) * BOARD_SIZE + col + 2] = true;
            numOfAvailable++;
        }
    }
    else if (!isWhite)
    {
        if (col > 1 && row > 1 &&
            fields[(row - 2) * BOARD_SIZE + col - 2] < 0 &&
            fields[(row - 1) * BOARD_SIZE + col - 1] >= 0 &&
            fields[(row - 1) * BOARD_SIZE + col - 1] / halfPawn != idx / halfPawn)
        {
            available[(row - 2) * BOARD_SIZE + col - 2] = true;
            numOfAvailable++;
        }
        if (col < BOARD_SIZE - 2 && row > 1 &&
            fields[(row - 2) * BOARD_SIZE + col + 2] < 0 &&
            fields[(row - 1) * BOARD_SIZE + col + 1] >= 0 &&
            fields[(row - 1) * BOARD_SIZE + col + 1] / halfPawn != idx / halfPawn)
        {
            available[(row - 2) * BOARD_SIZE + col + 2] = true;
            numOfAvailable++;
        }
    }
}

void setAvailableQueenKills(int* fields, int row, int col, int idx, bool* available, int& numOfAvailable)
{
    int halfPawn = PAWN_ROWS * BOARD_SIZE / 2;

        for (int r = row + 1, c = col - 1; r < BOARD_SIZE - 1 && c > 0; r++, c--)
        {
            if (fields[r * BOARD_SIZE + c] >= 0)
            {
                if (fields[r * BOARD_SIZE + c] / halfPawn != idx / halfPawn
                    && fields[(r + 1) * BOARD_SIZE + c - 1] < 0)
                {
                    available[(r + 1) * BOARD_SIZE + c - 1] = true;
                    numOfAvailable++;
                }
                break;
            }
        }
        for (int r = row + 1, c = col + 1; r < BOARD_SIZE - 1 && c < BOARD_SIZE - 1; r++, c++)
        {
            if (fields[r * BOARD_SIZE + c] >= 0)
            {
                if (fields[r * BOARD_SIZE + c] / halfPawn != idx / halfPawn
                    && fields[(r + 1) * BOARD_SIZE + c + 1] < 0)
                {
                    available[(r + 1) * BOARD_SIZE + c + 1] = true;
                    numOfAvailable++;
                }
                break;
            }
        }
        for (int r = row - 1, c = col - 1; r > 0 && c > 0; r--, c--)
        {
            if (fields[r * BOARD_SIZE + c] >= 0)
            {
                if (fields[r * BOARD_SIZE + c] / halfPawn != idx / halfPawn
                    && fields[(r - 1) * BOARD_SIZE + c - 1] < 0)
                {
                    available[(r - 1) * BOARD_SIZE + c - 1] = true;
                    numOfAvailable++;
                }
                break;
            }
        }
        for (int r = row - 1, c = col + 1; r > 0 && c < BOARD_SIZE - 1; r--, c++)
        {
            if (fields[r * BOARD_SIZE + c] >= 0)
            {
                if (fields[r * BOARD_SIZE + c] / halfPawn != idx / halfPawn
                    && fields[(r - 1) * BOARD_SIZE + c + 1] < 0)
                {
                    available[(r - 1) * BOARD_SIZE + c + 1] = true;
                    numOfAvailable++;
                }
                break;
            }
        }
}

void markAvailableFields(RectangleShape* fieldShapes, bool* available)
{
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        if (available[i])
            fieldShapes[i].setFillColor(Color::Color(125, 125, 125));
    }
}

void removePawn(int idx, int* rows, int* cols, int* fields)
{
    int targetIdx = fields[idx];
    rows[targetIdx] = -1;
    cols[targetIdx] = -1;
    fields[idx] = -1;
}

void handlePawnClick(int i, int* rows, int* cols, int* fields, RectangleShape* fieldShapes, bool* available, int& numOfAvailable,
    int& selectedPawnIdx, bool& performedOperation, bool isThereKill, bool* pawnHasKill, bool* isQueen, bool isChainKill = false)
{
    clearAvailableFields(available, numOfAvailable);
    if (isQueen[i])
    {
        if (isChainKill || pawnHasKill[i])
        {
            setAvailableQueenKills(fields, rows[i], cols[i], i, available, numOfAvailable);
        }
        else if (!isThereKill)
        {
            setAvailableQueenFields(rows[i], cols[i], available, fields, numOfAvailable);
        }
    }
    else
    {
        if (isChainKill)
        {
            setAvailableKills(fields, rows[i], cols[i], i, true, available, numOfAvailable);
            setAvailableKills(fields, rows[i], cols[i], i, false, available, numOfAvailable);
        }
        else if (!isThereKill)
        {
            setAvailableFields(rows[i], cols[i], i < (PAWN_ROWS* BOARD_SIZE / 2),
                available, fields, numOfAvailable);
        }
        else if (pawnHasKill[i])
        {
            setAvailableKills(fields, rows[i], cols[i], i, i < (PAWN_ROWS* BOARD_SIZE / 2), available, numOfAvailable);
        }
    }
    markAvailableFields(fieldShapes, available);
    selectedPawnIdx = i;
    performedOperation = true;
}

void markQueen(CircleShape* pawns, int idx)
{
    pawns[idx].setOutlineColor(Color::Yellow);
}

int trackPawnToRemove(int rowStart, int colStart, int rowEnd, int colEnd, int* fields)
{
    int diffR = rowEnd - rowStart > 0 ? 1 : -1;
    int diffC = colEnd - colStart > 0 ? 1 : -1;
    for (int r = rowStart + diffR, c = colStart + diffC; r != rowEnd; r += diffR, c += diffC)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            return (r * BOARD_SIZE + c);
    }
    return -1;
}

// from [start, end)
int getRandom(int start, int end)
{
    return rand() % (end - start) + start;
}

bool makeRandomAvailableMove(int* fields, int* rows, int* cols, bool* pawnHasKill, bool* isQueen, bool& blackTurn, bool* available, int& numOfWhite, int& numOfBlack, int pawnInChainKill = -1)
{
    bool isThereKill = false;
    int numOfPawnsWithKill = 0;
    int numOfAvailable = 0;
    clearAvailableFields(available, numOfAvailable);
    int targetPos = -1;
    int idx = blackTurn ? PAWN_ROWS * BOARD_SIZE / 2 - 1 : -1;
    if (pawnInChainKill >= 0)
    {
        idx = pawnInChainKill;
        if (isQueen[idx])
            setAvailableQueenKills(fields, rows[idx], cols[idx], idx, available, numOfAvailable);
        else
        {
            setAvailableKills(fields, rows[idx], cols[idx], idx, true, available, numOfAvailable);
            setAvailableKills(fields, rows[idx], cols[idx], idx, false, available, numOfAvailable);
        }

        
    }
    else {
        if (!blackTurn)
        {
            for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
            {
                pawnHasKill[i] = rows[i] >= 0 && (isQueen[i] ? hasQueenKill(fields, rows[i],
                    cols[i], i) : hasKill(fields, i, rows, cols));
                if (pawnHasKill[i])
                {
                    isThereKill = true;
                    numOfPawnsWithKill++;
                }
            }
        }
        else
        {
            for (int i = PAWN_ROWS * BOARD_SIZE / 2; i < PAWN_ROWS * BOARD_SIZE; i++)
            {
                pawnHasKill[i] = rows[i] >= 0 && (isQueen[i] ? hasQueenKill(fields, rows[i],
                    cols[i], i) : hasKill(fields, i, rows, cols));
                if (pawnHasKill[i])
                {
                    isThereKill = true;
                    numOfPawnsWithKill++;
                }
            }
        }
        if (isThereKill)
        {
            if (numOfPawnsWithKill == 0)
                cout << 0;
            int rndPawn = getRandom(0, numOfPawnsWithKill);
            int counter = -1;
            while (counter < rndPawn)
            {
                idx++;
                if (pawnHasKill[idx])
                {
                    counter++;
                }
            }
            if (isQueen[idx])
                setAvailableQueenKills(fields, rows[idx], cols[idx], idx, available, numOfAvailable);
            else
                setAvailableKills(fields, rows[idx], cols[idx], idx, idx < PAWN_ROWS * BOARD_SIZE / 2, available, numOfAvailable);
        }
        else
        {
            idx = blackTurn ? getRandom(PAWN_ROWS * BOARD_SIZE / 2, PAWN_ROWS * BOARD_SIZE) : getRandom(0, PAWN_ROWS * BOARD_SIZE / 2);
            while (rows[idx] < 0 || numOfAvailable == 0)
            {
                idx = blackTurn ? getRandom(PAWN_ROWS * BOARD_SIZE / 2, PAWN_ROWS * BOARD_SIZE) : getRandom(0, PAWN_ROWS * BOARD_SIZE / 2);
                numOfAvailable = 0;
                if (rows[idx] < 0) continue;
                if (isQueen[idx])
                {
                    setAvailableQueenFields(rows[idx], cols[idx], available, fields, numOfAvailable);
                }
                else
                {
                    setAvailableFields(rows[idx], cols[idx], idx < PAWN_ROWS* BOARD_SIZE / 2, available, fields, numOfAvailable);
                }
            }
            clearAvailableFields(available, numOfAvailable);
            if (isQueen[idx])
            {
                setAvailableQueenFields(rows[idx], cols[idx], available, fields, numOfAvailable);
            }
            else
            {
                setAvailableFields(rows[idx], cols[idx], idx < PAWN_ROWS* BOARD_SIZE / 2, available, fields, numOfAvailable);
            }
        }
    }
    if (numOfAvailable == 0)
        cout << 0;
    int rndMove = getRandom(0, numOfAvailable);
    int avCounter = -1;

    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        if (available[i])
        {
            avCounter++;
            if (avCounter == rndMove)
            {
                targetPos = i;
                break;
            }
        }
    }
    fields[rows[idx] * BOARD_SIZE + cols[idx]] = -1;
    int pawnToRemove;
    if ((pawnToRemove = trackPawnToRemove(rows[idx], cols[idx], targetPos / BOARD_SIZE, targetPos % BOARD_SIZE, fields)) >= 0)
    {
        if (fields[pawnToRemove] < PAWN_ROWS * BOARD_SIZE / 2)
            numOfWhite--;
        else
            numOfBlack--;
        removePawn(pawnToRemove, rows, cols, fields);
    }
    fields[targetPos] = idx;
    rows[idx] = targetPos / BOARD_SIZE;
    cols[idx] = targetPos % BOARD_SIZE;
    if ((rows[idx] + cols[idx]) % 2 == 1)
        cout << 0;
    bool blockChainKill = false;
    if ((idx >= PAWN_ROWS * BOARD_SIZE / 2
        && rows[idx] == 0) ||
        (idx < PAWN_ROWS * BOARD_SIZE / 2 &&
            rows[idx] == BOARD_SIZE - 1))
    {
        isQueen[idx] = true;
        blockChainKill = true;
    }
    int nextPawnInChainKill = -1;
    if (isThereKill && !blockChainKill && (isQueen[idx] ? hasQueenKill(fields, rows[idx],
        cols[idx], idx) : hasKill(fields, idx, rows, cols, true)))
    {
        nextPawnInChainKill = idx;
        return makeRandomAvailableMove(fields, rows, cols, pawnHasKill, isQueen, blackTurn, available, numOfWhite, numOfBlack, nextPawnInChainKill);
    }
    return numOfWhite > 0 && numOfBlack > 0;
}

int main()
{
    RenderWindow window{ VideoMode(WINDOW_WIDTH, WINDOW_HEIGHT), "Checkers" };
    RectangleShape* fieldShapes = new RectangleShape[BOARD_SIZE * BOARD_SIZE];
    CircleShape* pawns = new CircleShape[PAWN_ROWS * BOARD_SIZE];
    int* fields = new int[BOARD_SIZE * BOARD_SIZE];
    int* rows = new int[PAWN_ROWS * BOARD_SIZE];
    int* cols = new int[PAWN_ROWS * BOARD_SIZE];
    bool* pawnHasKill = new bool[PAWN_ROWS * BOARD_SIZE];
    bool* available = new bool[BOARD_SIZE * BOARD_SIZE];
    bool* isQueen = new bool[PAWN_ROWS * BOARD_SIZE];
    int selectedPawnIdx = -1;
    bool performedOperation = false;
    bool blackTurn = false;
    int pawnInChainKill = -1;
    int pawnToRemove = -1;
    bool blockChainKill = false;
    setupFields(fieldShapes, fields);
    setupPawns(pawns, fields, rows, cols, pawnHasKill, isQueen);
    unsigned t = 1640459141;
    srand(t);

    window.setFramerateLimit(25);
    Event event;
    int numOfAvailable = 0;
    bool isThereKill = false;
    int numOfWhite = PAWN_ROWS * BOARD_SIZE / 2;
    int numOfBlack = PAWN_ROWS * BOARD_SIZE / 2;

    while (true)
    {
        window.clear(Color::Black);
        window.pollEvent(event);
        if (event.type == Event::Closed)
        {
            window.close();
            break;
        }
        else if (event.type == Event::MouseButtonPressed)
        {
            makeRandomAvailableMove(fields, rows, cols, pawnHasKill, isQueen, blackTurn, available, numOfWhite, numOfBlack);
            blackTurn = !blackTurn;
            for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
                if(rows[i] >= 0) setPawnPosition(pawns[i], rows[i], cols[i]);
           /* performedOperation = false;
            recolorFields(fieldShapes);
            Vector2f mousePosition = (Vector2f)Mouse::getPosition(window);

            if (pawnInChainKill >= 0)
            {
                if (isClickInShape(pawns[pawnInChainKill], mousePosition))
                {
                    handlePawnClick(pawnInChainKill, rows, cols, fields, fieldShapes, available, numOfAvailable, selectedPawnIdx, 
                        performedOperation, isThereKill, pawnHasKill, isQueen, true);
                    
                }
            }
            else {
                if (!blackTurn)
                    for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
                    {
                        if (isClickInShape(pawns[i], mousePosition))
                        {
                            handlePawnClick(i, rows, cols, fields, fieldShapes, available, numOfAvailable, selectedPawnIdx, performedOperation, isThereKill, pawnHasKill, isQueen);
                            break;
                        }
                    }
                else
                    for (int i = PAWN_ROWS * BOARD_SIZE / 2; i < PAWN_ROWS * BOARD_SIZE; i++)
                    {
                        if (isClickInShape(pawns[i], mousePosition))
                        {
                            handlePawnClick(i, rows, cols, fields, fieldShapes, available, numOfAvailable, selectedPawnIdx, performedOperation, isThereKill, pawnHasKill, isQueen);
                            break;
                        }
                    }
            }
            if (!performedOperation && selectedPawnIdx >= 0)
            {
                for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
                {
                    if (available[i] && isClickInShape(fieldShapes[i], mousePosition))
                    {
                        setPawnPosition(pawns[selectedPawnIdx], i / BOARD_SIZE, i % BOARD_SIZE);
                        if ((pawnToRemove = trackPawnToRemove(rows[selectedPawnIdx], cols[selectedPawnIdx], i / BOARD_SIZE, i % BOARD_SIZE, fields)) >= 0)
                        {
                            pawns[fields[pawnToRemove]].setRadius(0);
                            removePawn(pawnToRemove, rows, cols, fields);
                        }
                        fields[rows[selectedPawnIdx] * BOARD_SIZE + cols[selectedPawnIdx]] = -1;
                        fields[i] = selectedPawnIdx;
                        rows[selectedPawnIdx] = i / BOARD_SIZE;
                        cols[selectedPawnIdx] = i % BOARD_SIZE;
                        blockChainKill = false;
                        if ((selectedPawnIdx >= PAWN_ROWS * BOARD_SIZE / 2
                            && rows[selectedPawnIdx] == 0) ||
                            (selectedPawnIdx < PAWN_ROWS * BOARD_SIZE / 2 &&
                                rows[selectedPawnIdx] == BOARD_SIZE - 1))
                        {
                            markQueen(pawns, selectedPawnIdx);
                            isQueen[selectedPawnIdx] = true;
                            blockChainKill = true;
                        }
      
                        clearAvailableFields(available, numOfAvailable);
                        pawnInChainKill = -1;
                        if (isThereKill && !blockChainKill && (isQueen[selectedPawnIdx] ? hasQueenKill(fields, rows[selectedPawnIdx], 
                            cols[selectedPawnIdx], selectedPawnIdx) : hasKill(fields, selectedPawnIdx, rows, cols, true)))
                        {
                            pawnInChainKill = selectedPawnIdx;
                        }
                        else
                        {
                            blackTurn = !blackTurn;
                            isThereKill = false;
                            if (!blackTurn)
                            {
                                for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
                                {
                                    pawnHasKill[i] = rows[i] >= 0 && (isQueen[i] ? hasQueenKill(fields, rows[i],
                                        cols[i], i) : hasKill(fields, i, rows, cols));
                                    if (pawnHasKill[i])
                                        isThereKill = true;
                                }
                            }
                            else
                            {
                                for (int i = PAWN_ROWS * BOARD_SIZE / 2; i < PAWN_ROWS * BOARD_SIZE; i++)
                                {
                                    pawnHasKill[i] = rows[i] >= 0 && (isQueen[i] ? hasQueenKill(fields, rows[i],
                                        cols[i], i) : hasKill(fields, i, rows, cols));
                                    if (pawnHasKill[i])
                                        isThereKill = true;
                                }
                            }
                        }
                        selectedPawnIdx = -1;
                        break;
                    }
                }
            }*/
            event.type = Event::MouseButtonReleased;
        }

        for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
            window.draw(fieldShapes[i]);
        for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
            if (rows[i] >= 0) window.draw(pawns[i]);
        
        window.display();
    }
    delete[] fields;
    delete[] pawns;
    return 0;
}