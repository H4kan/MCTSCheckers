
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <iostream>
#include <fstream>
#include <stdlib.h>
#include <time.h>
#include <chrono>
#include <SFML/Graphics.hpp>
#include <SFML/Window.hpp>
#include <thrust/device_ptr.h>
#include <thrust/reduce.h>
#include <curand_kernel.h>

#define WINDOW_WIDTH 800
#define WINDOW_HEIGHT 800
#define BOARD_SIZE 8
#define PAWN_ROWS 3
#define PAWN_SIZE 80

#define MAX_MOVES 50


#define QUEEN_VALUE 80
#define PAWN_VALUE 30
#define PIECE_ROW_ADV 1
#define PIECE_MIDDLE_CENTER 4
#define PIECE_MIDDLE_SIDE -2
#define PIECE_CENTER_GOALIES 8
#define PIECE_SIDE_GOALIES 8
#define PIECE_DOUBLE_CORNER 4

#define PLAYER_VS_AI 0
#define PLAYER_ONE 1
#define PLAYER_TWO 2

// this should be multiply of 1024 otherwise it will get ceiled up to nearest multiplication of 1024
#define NUM_OF_EVAL_ONE 10240
#define TREE_ITER_ONE 50
#define PARALLEL_PLAYER_ONE false

// this should be multiply of 1024 otherwise it will get ceiled up to nearest multiplication of 1024
#define NUM_OF_EVAL_TWO 102400
#define TREE_ITER_TWO 50
#define PARALLEL_PLAYER_TWO true

#define MAX_BLOCK 1024

#define BLOCK_SIZE_ONE (NUM_OF_EVAL_ONE < MAX_BLOCK ? NUM_OF_EVAL_ONE : MAX_BLOCK)
#define BLOCK_SIZE_TWO (NUM_OF_EVAL_TWO < MAX_BLOCK ? NUM_OF_EVAL_TWO : MAX_BLOCK)


#define BLOCK_SIZE_ONE_V dim3((NUM_OF_EVAL_ONE < MAX_BLOCK ? NUM_OF_EVAL_ONE : MAX_BLOCK), 1, 1)
#define BLOCK_SIZE_TWO_V dim3((NUM_OF_EVAL_TWO < MAX_BLOCK ? NUM_OF_EVAL_TWO : MAX_BLOCK), 1, 1)


#define BLOCK_NUM_ONE (NUM_OF_EVAL_ONE / (float)BLOCK_SIZE_ONE != NUM_OF_EVAL_ONE / BLOCK_SIZE_ONE ? NUM_OF_EVAL_ONE / BLOCK_SIZE_ONE + 1 : NUM_OF_EVAL_ONE / BLOCK_SIZE_ONE)
#define BLOCK_NUM_TWO (NUM_OF_EVAL_TWO / (float)BLOCK_SIZE_TWO != NUM_OF_EVAL_TWO / BLOCK_SIZE_TWO ? NUM_OF_EVAL_TWO / BLOCK_SIZE_TWO + 1 : NUM_OF_EVAL_TWO / BLOCK_SIZE_TWO)

#define BLOCK_NUM_ONE_V dim3((NUM_OF_EVAL_ONE / (float)BLOCK_SIZE_ONE != NUM_OF_EVAL_ONE / BLOCK_SIZE_ONE ? NUM_OF_EVAL_ONE / BLOCK_SIZE_ONE + 1 : NUM_OF_EVAL_ONE / BLOCK_SIZE_ONE), 1, 1)
#define BLOCK_NUM_TWO_V dim3((NUM_OF_EVAL_TWO / (float)BLOCK_SIZE_TWO != NUM_OF_EVAL_TWO / BLOCK_SIZE_TWO ? NUM_OF_EVAL_TWO / BLOCK_SIZE_TWO + 1 : NUM_OF_EVAL_TWO / BLOCK_SIZE_TWO), 1, 1)



using namespace sf;
using namespace std;

typedef struct node {
    int* rows;
    int* cols;
    int* fields;
    bool* isQueen;
    bool blackTurn;
    int lastKill;
    int childSize;
    node** childs;
    node* parent;
    float avgReward;
    int howManyVisits;
} node;

typedef struct fixedNode {
    int rows[PAWN_ROWS * BOARD_SIZE];
    int cols[PAWN_ROWS * BOARD_SIZE];
    int fields[BOARD_SIZE * BOARD_SIZE];
    bool isQueen[PAWN_ROWS * BOARD_SIZE];
} fixedNode;

__host__ void recolorFields(RectangleShape* fields)
{
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        bool isBlack = ((i / BOARD_SIZE) + (i % BOARD_SIZE)) % 2 == 0;
        if (isBlack)
            fields[i].setFillColor(Color::Black);
    }
}

__host__ void setupFields(RectangleShape* fieldShapes, int* fields)
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

__host__ void setPawnPosition(CircleShape& pawn, int row, int col)
{
    const Vector2f vecPos{ (float)(col * WINDOW_WIDTH / BOARD_SIZE + (WINDOW_WIDTH / BOARD_SIZE - PAWN_SIZE) / 2),
        (float)((BOARD_SIZE - 1 - row) * WINDOW_HEIGHT / BOARD_SIZE + (WINDOW_HEIGHT / BOARD_SIZE - PAWN_SIZE) / 2) };
    pawn.setPosition(vecPos);
}

__host__ void setupPawns(CircleShape* pawns, int* fields, int* rows, int* cols, bool* pawnHasKill, bool* isQueen)
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

__host__ bool isClickInShape(Shape& shape, Vector2f clickPos)
{
    Vector2f shapePosition = shape.getPosition();
    return clickPos.x >= shapePosition.x && clickPos.x <= shapePosition.x + shape.getLocalBounds().width
        && clickPos.y >= shapePosition.y && clickPos.y <= shapePosition.y + shape.getLocalBounds().height;
}

__host__ __device__ void clearAvailableFields(bool* available, int& numOfAvailable)
{
    numOfAvailable = 0;
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
        available[i] = false;
}

__host__ __device__ bool hasQueenKill(int* fields, int row, int col, int idx)
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

__host__ __device__ bool hasKill(int* fields, int idx, int* rows, int* cols, bool isChainKill = false)
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

__host__ __device__ void setAvailableFields(int row, int col, bool isWhite, bool* available, int* fields, int& numOfAvailable)
{
    bool shouldUpdateAvailable = available != nullptr;
    if (isWhite && row < BOARD_SIZE - 1)
    {
        if (col > 0 && fields[(row + 1) * BOARD_SIZE + col - 1] < 0)
        {
            if (shouldUpdateAvailable)
                available[(row + 1) * BOARD_SIZE + col - 1] = true;
            numOfAvailable++;
        }
        if (col < BOARD_SIZE - 1 && fields[(row + 1) * BOARD_SIZE + col + 1] < 0)
        {
            if (shouldUpdateAvailable)
                available[(row + 1) * BOARD_SIZE + col + 1] = true;
            numOfAvailable++;
        }
    }
    else if (!isWhite && row > 0)
    {
        if (col > 0 && fields[(row - 1) * BOARD_SIZE + col - 1] < 0)
        {
            if (shouldUpdateAvailable)
                available[(row - 1) * BOARD_SIZE + col - 1] = true;
            numOfAvailable++;
        }
        if (col < BOARD_SIZE - 1 && fields[(row - 1) * BOARD_SIZE + col + 1] < 0)
        {
            if (shouldUpdateAvailable)
                available[(row - 1) * BOARD_SIZE + col + 1] = true;
            numOfAvailable++;
        }
    }
}

__host__ __device__ void setAvailableQueenFields(int row, int col, bool* available, int* fields, int& numOfAvailable)
{
    bool shouldUpdateAvailable = available != nullptr;
    for (int r = row - 1, c = col - 1; r >= 0 && c >= 0; r--, c--)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;
        if (shouldUpdateAvailable)
            available[r * BOARD_SIZE + c] = true;
        numOfAvailable++;
    }
    for (int r = row + 1, c = col + 1; r < BOARD_SIZE && c < BOARD_SIZE; r++, c++)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;
        if (shouldUpdateAvailable)
            available[r * BOARD_SIZE + c] = true;
        numOfAvailable++;
    }
    for (int r = row - 1, c = col + 1; r >= 0 && c < BOARD_SIZE; r--, c++)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;
        if (shouldUpdateAvailable)
            available[r * BOARD_SIZE + c] = true;
        numOfAvailable++;
    }
    for (int r = row + 1, c = col - 1; r < BOARD_SIZE && c >= 0; r++, c--)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;
        if (shouldUpdateAvailable)
            available[r * BOARD_SIZE + c] = true;
        numOfAvailable++;
    }
}

__host__ __device__ void setAvailableKills(int* fields, int row, int col, int idx, bool isWhite, bool* available, int& numOfAvailable)
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

__host__ __device__ void setAvailableQueenKills(int* fields, int row, int col, int idx, bool* available, int& numOfAvailable)
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

__host__ void markAvailableFields(RectangleShape* fieldShapes, bool* available)
{
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        if (available[i])
            fieldShapes[i].setFillColor(Color::Color(125, 125, 125));
    }
}

__host__ __device__ void removePawn(int idx, int* rows, int* cols, int* fields)
{
    int targetIdx = fields[idx];
    rows[targetIdx] = -1;
    cols[targetIdx] = -1;
    fields[idx] = -1;
}

__host__ void handlePawnClick(int i, int* rows, int* cols, int* fields, RectangleShape* fieldShapes, bool* available, int& numOfAvailable,
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

__host__ void markQueen(CircleShape* pawns, int idx)
{
    pawns[idx].setOutlineColor(Color::Yellow);
}

__host__ __device__ int trackPawnToRemove(int rowStart, int colStart, int rowEnd, int colEnd, int* fields)
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
__host__ int h_getRandom(int start, int end)
{
    return rand() % (end - start) + start;
}

// from [start, end)
__device__ int d_getRandom(int start, int end, curandState* state)
{
    return end - ceilf(curand_uniform(state) * (end - start));
}

__host__ bool h_makeRandomAvailableMove(int* fields, int* rows, int* cols, bool* pawnHasKill, bool* isQueen, bool& blackTurn, bool* available, int& numOfWhite, int& numOfBlack, int pawnInChainKill = -1)
{
    bool isThereKill = false;
    int numOfPawnsWithKill = 0;
    int numOfAvailable = 0;
    clearAvailableFields(available, numOfAvailable);
    int targetPos = -1;
    int idx = blackTurn ? PAWN_ROWS * BOARD_SIZE / 2 - 1 : -1;
    if (pawnInChainKill >= 0)
    {
        isThereKill = true;

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
            int rndPawn = h_getRandom(0, numOfPawnsWithKill);
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
                setAvailableKills(fields, rows[idx], cols[idx], idx, idx < PAWN_ROWS* BOARD_SIZE / 2, available, numOfAvailable);
        }
        else
        {
            int numOfPossible = 0;
            int start = blackTurn ? PAWN_ROWS * BOARD_SIZE / 2 : 0;
            int end = blackTurn ? PAWN_ROWS * BOARD_SIZE : PAWN_ROWS * BOARD_SIZE / 2;
            for (int i = start; i < end; i++)
            {
                if (rows[i] >= 0)
                {
                    numOfAvailable = 0;
                    if (isQueen[i])
                    {
                        setAvailableQueenFields(rows[i], cols[i], nullptr, fields, numOfAvailable);
                    }
                    else
                    {
                        setAvailableFields(rows[i], cols[i], i < PAWN_ROWS* BOARD_SIZE / 2, nullptr, fields, numOfAvailable);
                    }
                    if (numOfAvailable > 0)
                    {
                        numOfPossible = numOfPossible + 1;
                        available[i] = true;
                    }
                }
            }
            // draw
            if (numOfPossible == 0)
            {
                numOfWhite = 0;
                numOfBlack = 0;
                return false;
            }
            int possibleIdx = h_getRandom(0, numOfPossible);
            int counter = 0;
            for (int i = start; i < end; i++)
            {
                if (available[i]) {
                    if (counter == possibleIdx)
                    {
                        idx = i;
                        break;
                    }
                    counter++;
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
    int rndMove = h_getRandom(0, numOfAvailable);
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
        return h_makeRandomAvailableMove(fields, rows, cols, pawnHasKill, isQueen, blackTurn, available, numOfWhite, numOfBlack, nextPawnInChainKill);
    }
    return numOfWhite > 0 && numOfBlack > 0;
}

__device__ bool d_makeRandomAvailableMove(int* fields, int* rows, int* cols, bool* pawnHasKill, bool* isQueen, bool& blackTurn, bool* available, int& numOfWhite, int& numOfBlack, curandState* state, int pawnInChainKill = -1)
{
    bool isThereKill = false;
    int numOfPawnsWithKill = 0;
    int numOfAvailable = 0;
    clearAvailableFields(available, numOfAvailable);
    int targetPos = -1;
    int idx = blackTurn ? PAWN_ROWS * BOARD_SIZE / 2 - 1 : -1;

    if (pawnInChainKill >= 0)
    {
        isThereKill = true;

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
            int rndPawn = d_getRandom(0, numOfPawnsWithKill, state);
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
                setAvailableKills(fields, rows[idx], cols[idx], idx, idx < PAWN_ROWS* BOARD_SIZE / 2, available, numOfAvailable);
        }
        else
        {
            int numOfPossible = 0;
            int start = blackTurn ? PAWN_ROWS * BOARD_SIZE / 2 : 0;
            int end = blackTurn ? PAWN_ROWS * BOARD_SIZE : PAWN_ROWS * BOARD_SIZE / 2;
            for (int i = start; i < end; i++)
            {
                if (rows[i] >= 0)
                {
                    numOfAvailable = 0;
                    if (isQueen[i])
                    {
                        setAvailableQueenFields(rows[i], cols[i], nullptr, fields, numOfAvailable);
                    }
                    else
                    {
                        setAvailableFields(rows[i], cols[i], i < PAWN_ROWS* BOARD_SIZE / 2, nullptr, fields, numOfAvailable);
                    }
                    if (numOfAvailable > 0)
                    {
                        numOfPossible = numOfPossible + 1;
                        available[i] = true;
                    }
                }
            }
            // draw
            if (numOfPossible == 0)
            {
                numOfWhite = 0;
                numOfBlack = 0;
                return false;
            }
            int possibleIdx = d_getRandom(0, numOfPossible, state);
            int counter = 0;
            for (int i = start; i < end; i++)
            {
                if (available[i]) {
                    if (counter == possibleIdx)
                    {
                        idx = i;
                        break;
                    }
                    counter++;
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
    int rndMove = d_getRandom(0, numOfAvailable, state);
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
        return d_makeRandomAvailableMove(fields, rows, cols, pawnHasKill, isQueen, blackTurn, available, numOfWhite, numOfBlack, state, nextPawnInChainKill);
    }
    return numOfWhite > 0 && numOfBlack > 0;
}

__host__ node* initNode(int* fields, int* rows, int* cols, bool* isQueen, bool blackTurn)
{
    node* state = new node;
    state->fields = new int[BOARD_SIZE * BOARD_SIZE];
    memcpy(state->fields, fields, BOARD_SIZE * BOARD_SIZE * sizeof(int));
    state->rows = new int[PAWN_ROWS * BOARD_SIZE];
    memcpy(state->rows, rows, PAWN_ROWS * BOARD_SIZE * sizeof(int));
    state->cols = new int[PAWN_ROWS * BOARD_SIZE];
    memcpy(state->cols, cols, PAWN_ROWS * BOARD_SIZE * sizeof(int));
    state->isQueen = new bool[PAWN_ROWS * BOARD_SIZE];
    memcpy(state->isQueen, isQueen, PAWN_ROWS * BOARD_SIZE * sizeof(bool));
    state->childs = nullptr;
    state->blackTurn = blackTurn;
    state->lastKill = -1;
    state->childSize = 0;
    state->avgReward = 0;
    state->howManyVisits = 0;

    return state;
}

__host__ void expandForPawnKills(int* fields, int row, int col, int idx, bool isWhite, node* root, bool changeTurn = true)
{
    int halfPawn = PAWN_ROWS * BOARD_SIZE / 2;
    if (isWhite)
    {
        if (col > 1 && row < BOARD_SIZE - 2 &&
            fields[(row + 2) * BOARD_SIZE + col - 2] < 0 &&
            fields[(row + 1) * BOARD_SIZE + col - 1] >= 0 &&
            fields[(row + 1) * BOARD_SIZE + col - 1] / halfPawn != idx / halfPawn)
        {
            root->childSize = root->childSize + 1;
            node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
            if (newChilds == nullptr)
            {
                root->childSize = root->childSize - 1;
                return;
            }
            else root->childs = newChilds;

            node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, (changeTurn ? !(root->blackTurn) : root->blackTurn));

            child->rows[idx] = row + 2;
            child->cols[idx] = col - 2;

            removePawn(trackPawnToRemove(row, col, child->rows[idx], child->cols[idx], child->fields), child->rows, child->cols, child->fields);

            child->fields[row * BOARD_SIZE + col] = -1;
            child->fields[(row + 2) * BOARD_SIZE + col - 2] = idx;


            if ((child->isQueen[idx] ? hasQueenKill(child->fields, child->rows[idx], child->cols[idx], idx) : hasKill(child->fields, idx, child->rows, child->cols, true)))
                child->lastKill = idx;

            if ((idx < PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == BOARD_SIZE - 1)
                || (idx >= PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == 0))
            {
                if (!child->isQueen[idx])
                    child->lastKill = -1;
                child->isQueen[idx] = true;
            }

            root->childs[root->childSize - 1] = child;
            child->parent = root;
        }

        if (col < BOARD_SIZE - 2 && row < BOARD_SIZE - 2 &&
            fields[(row + 2) * BOARD_SIZE + col + 2] < 0 &&
            fields[(row + 1) * BOARD_SIZE + col + 1] >= 0 &&
            fields[(row + 1) * BOARD_SIZE + col + 1] / halfPawn != idx / halfPawn)
        {
            root->childSize = root->childSize + 1;
            node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
            if (newChilds == nullptr)
            {
                root->childSize = root->childSize - 1;
                return;
            }
            else root->childs = newChilds;

            node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, (changeTurn ? !(root->blackTurn) : root->blackTurn));

            child->rows[idx] = row + 2;
            child->cols[idx] = col + 2;

            removePawn(trackPawnToRemove(row, col, child->rows[idx], child->cols[idx], child->fields), child->rows, child->cols, child->fields);

            child->fields[row * BOARD_SIZE + col] = -1;
            child->fields[(row + 2) * BOARD_SIZE + col + 2] = idx;

            if ((child->isQueen[idx] ? hasQueenKill(child->fields, child->rows[idx], child->cols[idx], idx) : hasKill(child->fields, idx, child->rows, child->cols, true)))
                child->lastKill = idx;

            if ((idx < PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == BOARD_SIZE - 1)
                || (idx >= PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == 0))
            {
                if (!child->isQueen[idx])
                    child->lastKill = -1;
                child->isQueen[idx] = true;
            }

            root->childs[root->childSize - 1] = child;
            child->parent = root;
        }
    }
    else if (!isWhite)
    {
        if (col > 1 && row > 1 &&
            fields[(row - 2) * BOARD_SIZE + col - 2] < 0 &&
            fields[(row - 1) * BOARD_SIZE + col - 1] >= 0 &&
            fields[(row - 1) * BOARD_SIZE + col - 1] / halfPawn != idx / halfPawn)
        {
            root->childSize = root->childSize + 1;
            node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
            if (newChilds == nullptr)
            {
                root->childSize = root->childSize - 1;
                return;
            }
            else root->childs = newChilds;

            node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, (changeTurn ? !(root->blackTurn) : root->blackTurn));

            child->rows[idx] = row - 2;
            child->cols[idx] = col - 2;

            removePawn(trackPawnToRemove(row, col, child->rows[idx], child->cols[idx], child->fields), child->rows, child->cols, child->fields);

            child->fields[row * BOARD_SIZE + col] = -1;
            child->fields[(row - 2) * BOARD_SIZE + col - 2] = idx;

            if ((child->isQueen[idx] ? hasQueenKill(child->fields, child->rows[idx], child->cols[idx], idx) : hasKill(child->fields, idx, child->rows, child->cols, true)))
                child->lastKill = idx;

            if ((idx < PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == BOARD_SIZE - 1)
                || (idx >= PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == 0))
            {
                if (!child->isQueen[idx])
                    child->lastKill = -1;
                child->isQueen[idx] = true;
            }

            root->childs[root->childSize - 1] = child;
            child->parent = root;
        }
        if (col < BOARD_SIZE - 2 && row > 1 &&
            fields[(row - 2) * BOARD_SIZE + col + 2] < 0 &&
            fields[(row - 1) * BOARD_SIZE + col + 1] >= 0 &&
            fields[(row - 1) * BOARD_SIZE + col + 1] / halfPawn != idx / halfPawn)
        {
            root->childSize = root->childSize + 1;
            node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
            if (newChilds == nullptr)
            {
                root->childSize = root->childSize - 1;
                return;
            }
            else root->childs = newChilds;

            node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, (changeTurn ? !(root->blackTurn) : root->blackTurn));

            child->rows[idx] = row - 2;
            child->cols[idx] = col + 2;

            removePawn(trackPawnToRemove(row, col, child->rows[idx], child->cols[idx], child->fields), child->rows, child->cols, child->fields);

            child->fields[row * BOARD_SIZE + col] = -1;
            child->fields[(row - 2) * BOARD_SIZE + col + 2] = idx;

            if ((child->isQueen[idx] ? hasQueenKill(child->fields, child->rows[idx], child->cols[idx], idx) : hasKill(child->fields, idx, child->rows, child->cols, true)))
                child->lastKill = idx;

            if ((idx < PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == BOARD_SIZE - 1)
                || (idx >= PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == 0))
            {
                if (!child->isQueen[idx])
                    child->lastKill = -1;
                child->isQueen[idx] = true;
            }

            root->childs[root->childSize - 1] = child;
            child->parent = root;
        }
    }
}

__host__ void expandForQueenKill(int* fields, int row, int col, int idx, node* root, bool changeTurn = true)
{
    int halfPawn = PAWN_ROWS * BOARD_SIZE / 2;

    for (int r = row + 1, c = col - 1; r < BOARD_SIZE - 1 && c > 0; r++, c--)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
        {
            if (fields[r * BOARD_SIZE + c] / halfPawn != idx / halfPawn
                && fields[(r + 1) * BOARD_SIZE + c - 1] < 0)
            {
                root->childSize = root->childSize + 1;
                node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
                if (newChilds == nullptr)
                {
                    return;
                }
                else root->childs = newChilds;

                node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, (changeTurn ? !(root->blackTurn) : root->blackTurn));

                child->rows[idx] = r + 1;
                child->cols[idx] = c - 1;

                removePawn(trackPawnToRemove(row, col, child->rows[idx], child->cols[idx], child->fields), child->rows, child->cols, child->fields);

                child->fields[row * BOARD_SIZE + col] = -1;
                child->fields[(r + 1) * BOARD_SIZE + c - 1] = idx;

                if ((child->isQueen[idx] ? hasQueenKill(child->fields, child->rows[idx], child->cols[idx], idx) : hasKill(child->fields, idx, child->rows, child->cols, true)))
                    child->lastKill = idx;

                root->childs[root->childSize - 1] = child;
                child->parent = root;
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
                root->childSize = root->childSize + 1;
                node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
                if (newChilds == nullptr)
                {
                    return;
                }
                else root->childs = newChilds;

                node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, (changeTurn ? !(root->blackTurn) : root->blackTurn));

                child->rows[idx] = r + 1;
                child->cols[idx] = c + 1;

                removePawn(trackPawnToRemove(row, col, child->rows[idx], child->cols[idx], child->fields), child->rows, child->cols, child->fields);

                child->fields[row * BOARD_SIZE + col] = -1;
                child->fields[(r + 1) * BOARD_SIZE + c + 1] = idx;

                if ((child->isQueen[idx] ? hasQueenKill(child->fields, child->rows[idx], child->cols[idx], idx) : hasKill(child->fields, idx, child->rows, child->cols, true)))
                    child->lastKill = idx;

                root->childs[root->childSize - 1] = child;
                child->parent = root;
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
                root->childSize = root->childSize + 1;
                node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
                if (newChilds == nullptr)
                {
                    return;
                }
                else root->childs = newChilds;

                node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, (changeTurn ? !(root->blackTurn) : root->blackTurn));

                child->rows[idx] = r - 1;
                child->cols[idx] = c - 1;

                removePawn(trackPawnToRemove(row, col, child->rows[idx], child->cols[idx], child->fields), child->rows, child->cols, child->fields);

                child->fields[row * BOARD_SIZE + col] = -1;
                child->fields[(r - 1) * BOARD_SIZE + c - 1] = idx;

                if ((child->isQueen[idx] ? hasQueenKill(child->fields, child->rows[idx], child->cols[idx], idx) : hasKill(child->fields, idx, child->rows, child->cols, true)))
                    child->lastKill = idx;

                root->childs[root->childSize - 1] = child;
                child->parent = root;
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
                root->childSize = root->childSize + 1;
                node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
                if (newChilds == nullptr)
                {
                    return;
                }
                else root->childs = newChilds;

                node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, (changeTurn ? !(root->blackTurn) : root->blackTurn));

                child->rows[idx] = r - 1;
                child->cols[idx] = c + 1;

                removePawn(trackPawnToRemove(row, col, child->rows[idx], child->cols[idx], child->fields), child->rows, child->cols, child->fields);

                child->fields[row * BOARD_SIZE + col] = -1;
                child->fields[(r - 1) * BOARD_SIZE + c + 1] = idx;

                if ((child->isQueen[idx] ? hasQueenKill(child->fields, child->rows[idx], child->cols[idx], idx) : hasKill(child->fields, idx, child->rows, child->cols, true)))
                    child->lastKill = idx;

                root->childs[root->childSize - 1] = child;
                child->parent = root;
            }
            break;
        }
    }
}

__host__ void expandForPawnMoves(int row, int col, int idx, int* fields, node* root)
{
    if (!(root->blackTurn) && row < BOARD_SIZE - 1)
    {
        if (col > 0 && fields[(row + 1) * BOARD_SIZE + col - 1] < 0)
        {
            root->childSize = root->childSize + 1;
            node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
            if (newChilds == nullptr)
            {
                return;
            }
            else root->childs = newChilds;

            node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, !(root->blackTurn));

            child->rows[idx] = row + 1;
            child->cols[idx] = col - 1;
            child->fields[row * BOARD_SIZE + col] = -1;
            child->fields[(row + 1) * BOARD_SIZE + col - 1] = idx;
            if ((idx < PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == BOARD_SIZE - 1)
                || (idx >= PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == 0))
                child->isQueen[idx] = true;

            root->childs[root->childSize - 1] = child;
            child->parent = root;
        }
        if (col < BOARD_SIZE - 1 && fields[(row + 1) * BOARD_SIZE + col + 1] < 0)
        {
            root->childSize = root->childSize + 1;
            node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
            if (newChilds == nullptr)
            {
                return;
            }
            else root->childs = newChilds;

            node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, !(root->blackTurn));

            child->rows[idx] = row + 1;
            child->cols[idx] = col + 1;
            child->fields[row * BOARD_SIZE + col] = -1;
            child->fields[(row + 1) * BOARD_SIZE + col + 1] = idx;
            if ((idx < PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == BOARD_SIZE - 1)
                || (idx >= PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == 0))
                child->isQueen[idx] = true;

            root->childs[root->childSize - 1] = child;
            child->parent = root;
        }
    }
    else if (root->blackTurn && row > 0)
    {
        if (col > 0 && fields[(row - 1) * BOARD_SIZE + col - 1] < 0)
        {
            root->childSize = root->childSize + 1;
            node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
            if (newChilds == nullptr)
            {
                root->childSize = root->childSize - 1;
                return;
            }
            else root->childs = newChilds;

            node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, !(root->blackTurn));

            child->rows[idx] = row - 1;
            child->cols[idx] = col - 1;
            child->fields[row * BOARD_SIZE + col] = -1;
            child->fields[(row - 1) * BOARD_SIZE + col - 1] = idx;
            if ((idx < PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == BOARD_SIZE - 1)
                || (idx >= PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == 0))
                child->isQueen[idx] = true;

            root->childs[root->childSize - 1] = child;
            child->parent = root;
        }
        if (col < BOARD_SIZE - 1 && fields[(row - 1) * BOARD_SIZE + col + 1] < 0)
        {
            root->childSize = root->childSize + 1;
            node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
            if (newChilds == nullptr)
            {
                root->childSize = root->childSize - 1;
                return;
            }
            else root->childs = newChilds;

            node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, !(root->blackTurn));

            child->rows[idx] = row - 1;
            child->cols[idx] = col + 1;
            child->fields[row * BOARD_SIZE + col] = -1;
            child->fields[(row - 1) * BOARD_SIZE + col + 1] = idx;
            if ((idx < PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == BOARD_SIZE - 1)
                || (idx >= PAWN_ROWS * BOARD_SIZE / 2 && child->rows[idx] == 0))
                child->isQueen[idx] = true;

            root->childs[root->childSize - 1] = child;
            child->parent = root;
        }
    }
}

__host__ void expandForQueenMoves(int row, int col, int idx, int* fields, node* root)
{
    for (int r = row - 1, c = col - 1; r >= 0 && c >= 0; r--, c--)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;

        root->childSize = root->childSize + 1;
        node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
        if (newChilds == nullptr)
        {
            root->childSize = root->childSize - 1;
            return;
        }
        else root->childs = newChilds;

        node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, !(root->blackTurn));

        child->rows[idx] = r;
        child->cols[idx] = c;
        child->fields[row * BOARD_SIZE + col] = -1;
        child->fields[r * BOARD_SIZE + c] = idx;

        root->childs[root->childSize - 1] = child;
        child->parent = root;
    }
    for (int r = row + 1, c = col + 1; r < BOARD_SIZE && c < BOARD_SIZE; r++, c++)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;

        root->childSize = root->childSize + 1;
        node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
        if (newChilds == nullptr)
        {
            root->childSize = root->childSize - 1;
            return;
        }
        else root->childs = newChilds;

        node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, !(root->blackTurn));

        child->rows[idx] = r;
        child->cols[idx] = c;
        child->fields[row * BOARD_SIZE + col] = -1;
        child->fields[r * BOARD_SIZE + c] = idx;

        root->childs[root->childSize - 1] = child;
        child->parent = root;
    }
    for (int r = row - 1, c = col + 1; r >= 0 && c < BOARD_SIZE; r--, c++)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;

        root->childSize = root->childSize + 1;
        node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
        if (newChilds == nullptr)
        {
            root->childSize = root->childSize - 1;
            return;
        }
        else root->childs = newChilds;

        node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, !(root->blackTurn));

        child->rows[idx] = r;
        child->cols[idx] = c;
        child->fields[row * BOARD_SIZE + col] = -1;
        child->fields[r * BOARD_SIZE + c] = idx;

        root->childs[root->childSize - 1] = child;
        child->parent = root;
    }
    for (int r = row + 1, c = col - 1; r < BOARD_SIZE && c >= 0; r++, c--)
    {
        if (fields[r * BOARD_SIZE + c] >= 0)
            break;

        root->childSize = root->childSize + 1;
        node** newChilds = (node**)realloc(root->childs, root->childSize * sizeof(node*));
        if (newChilds == nullptr)
        {
            root->childSize = root->childSize - 1;
            return;
        }
        else root->childs = newChilds;

        node* child = initNode(root->fields, root->rows, root->cols, root->isQueen, !(root->blackTurn));

        child->rows[idx] = r;
        child->cols[idx] = c;
        child->fields[row * BOARD_SIZE + col] = -1;
        child->fields[r * BOARD_SIZE + c] = idx;

        root->childs[root->childSize - 1] = child;
        child->parent = root;
    }
}

__host__ void expandNode(node* root)
{
    if (root->lastKill >= 0)
    {

        if (root->isQueen[root->lastKill])
        {
            expandForQueenKill(root->fields, root->rows[root->lastKill], root->cols[root->lastKill], root->lastKill, root, false);
        }
        else
        {
            expandForPawnKills(root->fields, root->rows[root->lastKill], root->cols[root->lastKill], root->lastKill, true, root, false);
            expandForPawnKills(root->fields, root->rows[root->lastKill], root->cols[root->lastKill], root->lastKill, false, root, false);
        }
        return;

    }

    int start = root->blackTurn ? PAWN_ROWS * BOARD_SIZE / 2 : 0;
    int end = root->blackTurn ? PAWN_ROWS * BOARD_SIZE : PAWN_ROWS * BOARD_SIZE / 2;
    bool isThereKill = false;

    for (int i = start; i < end; i++)
    {
        if (root->rows[i] >= 0)
        {
            if (root->isQueen[i] && hasQueenKill(root->fields, root->rows[i], root->cols[i], i))
            {
                expandForQueenKill(root->fields, root->rows[i], root->cols[i], i, root);
                isThereKill = true;
            }
            else if (hasKill(root->fields, i, root->rows, root->cols))
            {
                expandForPawnKills(root->fields, root->rows[i], root->cols[i], i, !(root->blackTurn), root);
                isThereKill = true;
            }
        }

    }
    if (isThereKill) return;

    for (int i = start; i < end; i++)
    {
        if (root->rows[i] >= 0)
        {
            if (root->isQueen[i])
            {
                expandForQueenMoves(root->rows[i], root->cols[i], i, root->fields, root);
            }
            else
            {
                expandForPawnMoves(root->rows[i], root->cols[i], i, root->fields, root);
            }
        }
    }
}

__host__ float getUCBValue(node* parent, node* child)
{
    if (child->howManyVisits == 0) return INFINITY;
    return (float)(child->avgReward + 2 * sqrt(log(parent->howManyVisits) / (float)child->howManyVisits));
}

__host__ void freeNode(node* root)
{
    delete[] root->fields;
    delete[] root->rows;
    delete[] root->cols;
    delete[] root->isQueen;

    for (int i = 0; i < root->childSize; i++)
        delete root->childs[i];

    if (root->childs != nullptr)
        delete[] root->childs;
    delete root;
}

// inspired by wischk checkers program evalutaion function
// http://people.cs.uchicago.edu/~wiseman/checkers/
__host__ __device__ float evaluatePositionValue(int* rows, int* cols, bool* isQueen, bool blackEval)
{
    float bMaterialValue = 0;
    float wMaterialValue = 0;
    float tscore = 0;
    for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
    {
        if (rows[i] >= 0)
        {
            if (isQueen[i]) wMaterialValue += QUEEN_VALUE;
            else wMaterialValue += PAWN_VALUE;

            if ((rows[i] == 3 && cols[i] == 3)
                || (rows[i] == 4 && cols[i] == 4)
                || (rows[i] == 5 && cols[i] == 3)
                || (rows[i] == 4 && cols[i] == 2))
                tscore -= PIECE_MIDDLE_CENTER;

            if ((rows[i] == 3 && cols[i] == 1)
                || (rows[i] == 4 && cols[i] == 0)
                || (rows[i] == 5 && cols[i] == 7)
                || (rows[i] == 4 && cols[i] == 6))
                tscore -= PIECE_MIDDLE_SIDE;

            if ((rows[i] == 0 && cols[i] == 0)
                || (rows[i] == 0 && cols[i] == 6))
                tscore -= PIECE_SIDE_GOALIES;


            if ((rows[i] == 0 && cols[i] == 2)
                || (rows[i] == 0 && cols[i] == 4))
                tscore -= PIECE_CENTER_GOALIES;

            if ((rows[i] == 0 && cols[i] == 6)
                || (rows[i] == 1 && cols[i] == 7))
                tscore -= PIECE_DOUBLE_CORNER;

            tscore -= rows[i] * PIECE_ROW_ADV;
        }
    }
    for (int i = PAWN_ROWS * BOARD_SIZE / 2; i < PAWN_ROWS * BOARD_SIZE; i++)
    {
        if (rows[i] >= 0)
        {
            if (isQueen[i]) bMaterialValue += QUEEN_VALUE;
            else bMaterialValue += PAWN_VALUE;

            if ((rows[i] == 3 && cols[i] == 3)
                || (rows[i] == 4 && cols[i] == 4)
                || (rows[i] == 5 && cols[i] == 3)
                || (rows[i] == 4 && cols[i] == 2))
                tscore += PIECE_MIDDLE_CENTER;

            if ((rows[i] == 3 && cols[i] == 1)
                || (rows[i] == 4 && cols[i] == 0)
                || (rows[i] == 5 && cols[i] == 7)
                || (rows[i] == 4 && cols[i] == 6))
                tscore += PIECE_MIDDLE_SIDE;

            if ((rows[i] == 7 && cols[i] == 1)
                || (rows[i] == 7 && cols[i] == 7))
                tscore += PIECE_SIDE_GOALIES;

            if ((rows[i] == 7 && cols[i] == 3)
                || (rows[i] == 7 && cols[i] == 5))
                tscore += PIECE_CENTER_GOALIES;

            if ((rows[i] == 7 && cols[i] == 1)
                || (rows[i] == 6 && cols[i] == 0))
                tscore += PIECE_DOUBLE_CORNER;

            tscore += (7 - rows[i]) * PIECE_ROW_ADV;
        }
    }
    float maxMaterial = bMaterialValue > wMaterialValue ? bMaterialValue : wMaterialValue;
    float minMaterial = bMaterialValue < wMaterialValue ? bMaterialValue : wMaterialValue;
    tscore += (bMaterialValue - wMaterialValue) * maxMaterial / (minMaterial + 1);
    if (isnan(tscore))
    {
        tscore = 1;
    }
    return tscore * (blackEval ? 1 : -1);
}

template <unsigned int blockSize>
__device__ void warpReduce(volatile float* sdata, unsigned int tid) {
    if (blockSize >= 64) sdata[tid] += sdata[tid + 32];
    if (blockSize >= 32) sdata[tid] += sdata[tid + 16];
    if (blockSize >= 16) sdata[tid] += sdata[tid + 8];
    if (blockSize >= 8) sdata[tid] += sdata[tid + 4];
    if (blockSize >= 4) sdata[tid] += sdata[tid + 2];
    if (blockSize >= 2) sdata[tid] += sdata[tid + 1];
}

void copyToFixedNode(node* root, fixedNode* fixed)
{
    for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
    {
        fixed->cols[i] = root->cols[i];
        fixed->rows[i] = root->rows[i];
        fixed->isQueen[i] = root->isQueen[i];
    }
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        fixed->fields[i] = root->fields[i];
    }
}

template <unsigned int blockSize>
__global__ void d_runSimulation(fixedNode* root, float* rewards, bool blackTurn, int lastKill, bool blackEval, int g_numOfWhite, int g_numOfBlack)
{
    extern __shared__ volatile float sumRewards[MAX_BLOCK];
    unsigned int tid = threadIdx.x;
    int fields[BOARD_SIZE * BOARD_SIZE];
    int rows[PAWN_ROWS * BOARD_SIZE];
    int cols[PAWN_ROWS * BOARD_SIZE];
    bool isQueen[PAWN_ROWS * BOARD_SIZE];
    //int* fields = (int*)malloc( * sizeof(int));
    //if (fields == nullptr)
    //{
    //    return;
    //}
 /*   int* rows = (int*)malloc(PAWN_ROWS * BOARD_SIZE * sizeof(int));
    if (rows == nullptr)
    {
        free(fields);
        return;
    }
    int* cols = (int*)malloc(PAWN_ROWS * BOARD_SIZE * sizeof(int));
    if (cols == nullptr)
    {
        free(fields);
        free(rows);
        return;
    }
    bool* isQueen = (bool*)malloc(PAWN_ROWS * BOARD_SIZE * sizeof(bool));
    if (isQueen == nullptr)
    {
        free(fields);
        free(rows);
        free(cols);
        return;
    }*/


    curandState state;

    curand_init(clock64(), tid, 0, &state);


    int numOfWhite = g_numOfWhite, numOfBlack = g_numOfBlack;

    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
        fields[i] = root->fields[i];
    for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
    {
        rows[i] = root->rows[i];
        cols[i] = root->cols[i];
        isQueen[i] = root->isQueen[i];
    }

    bool available[PAWN_ROWS * BOARD_SIZE];
    bool pawnHasKill[PAWN_ROWS * BOARD_SIZE];

    if (lastKill >= 0)
    {
        d_makeRandomAvailableMove(fields, rows, cols, pawnHasKill, isQueen,
            blackTurn, available, numOfWhite, numOfBlack, &state, lastKill);
    }
    for (int i = 0; i < MAX_MOVES; i++)
    {
        if (!d_makeRandomAvailableMove(fields, rows, cols, pawnHasKill, isQueen,
            blackTurn, available, numOfWhite, numOfBlack, &state)) break;
        blackTurn = !blackTurn;
    }
    sumRewards[tid] = evaluatePositionValue(rows, cols, isQueen, blackEval);
    __syncthreads();

    if (blockSize >= 512) { if (tid < 256) { sumRewards[tid] += sumRewards[tid + 256]; } __syncthreads(); }
    if (blockSize >= 256) { if (tid < 128) { sumRewards[tid] += sumRewards[tid + 128]; } __syncthreads(); }
    if (blockSize >= 128) { if (tid < 64) { sumRewards[tid] += sumRewards[tid + 64]; } __syncthreads(); }
    if (tid < 32) warpReduce<blockSize>(sumRewards, tid);
    if (tid == 0) rewards[blockIdx.x] = sumRewards[0];

}

bool d_initMemory(float** d_rewards, fixedNode** d_fixed, int blockNum)
{
    cudaError_t cudaStatus;

    cudaStatus = cudaMalloc((void**)d_rewards, blockNum * sizeof(float));
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMalloc failed!");
        return false;
    }
    cudaStatus = cudaMalloc((void**)d_fixed, sizeof(fixedNode));
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMalloc failed!");
        cudaFree(d_rewards);
        return false;
    }

    return true;
}

void d_freeMemory(float* d_rewards, fixedNode* d_fixed)
{
    cudaFree(d_rewards);
    cudaFree(d_fixed);
}

bool deviceMakeEvaluation(node* root, bool blackEval, int player, float* d_rewards, fixedNode* d_fixed, std::chrono::nanoseconds* timeStamps)
{
    int numOfEvaluations = (player == PLAYER_ONE ? NUM_OF_EVAL_ONE : NUM_OF_EVAL_TWO);

    unsigned int blockSize = min(numOfEvaluations, 1024);
    unsigned int blockNum = (int)ceil(numOfEvaluations / (float)blockSize);

    cudaError_t cudaStatus;

    fixedNode* h_fixed = (fixedNode*)malloc(sizeof(fixedNode));
    copyToFixedNode(root, h_fixed);

    auto gpuMemAllocStart1 = std::chrono::high_resolution_clock::now();
    cudaStatus = cudaMemcpy(d_fixed, h_fixed, sizeof(fixedNode), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMemcpy failed!");
        return false;
    }
    auto gpuMemAllocEnd1 = std::chrono::high_resolution_clock::now();
    int baseNumOfWhite = 0;
    int baseNumOfBlack = 0;

    for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
        if (root->rows[i] >= 0) baseNumOfWhite++;
    for (int i = PAWN_ROWS * BOARD_SIZE / 2; i < PAWN_ROWS * BOARD_SIZE; i++)
        if (root->rows[i] >= 0) baseNumOfBlack++;

    auto deviceStart1 = std::chrono::high_resolution_clock::now();

    if (player == PLAYER_ONE)
    {
        d_runSimulation<BLOCK_SIZE_ONE> << < BLOCK_NUM_ONE_V, BLOCK_SIZE_ONE_V, MAX_BLOCK * sizeof(float) >> > (d_fixed, d_rewards, root->blackTurn, root->lastKill, blackEval, baseNumOfWhite, baseNumOfBlack);
    }
    else
    {
        d_runSimulation<BLOCK_SIZE_TWO> << <BLOCK_NUM_TWO_V, BLOCK_SIZE_TWO_V, MAX_BLOCK * sizeof(float) >> > (d_fixed, d_rewards, root->blackTurn, root->lastKill, blackEval, baseNumOfWhite, baseNumOfBlack);
    }

    cudaStatus = cudaDeviceSynchronize();
    auto deviceEnd1 = std::chrono::high_resolution_clock::now();

    if (cudaStatus != cudaSuccess)
    {
        fprintf(stderr, "cudaDeviceSynchronize failed");
        return false;
    }

    float* rewards = (float*)malloc(blockNum * sizeof(float));
    auto gpuMemAllocStart2 = std::chrono::high_resolution_clock::now();
    cudaStatus = cudaMemcpy(rewards, d_rewards, blockNum * sizeof(float), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "cudaMemcpy failed!");
        return false;
    }
    thrust::device_ptr<float> dev_ptr = thrust::device_pointer_cast(d_rewards);
    auto gpuMemAllocEnd2 = std::chrono::high_resolution_clock::now();
    
    auto deviceStart2 = std::chrono::high_resolution_clock::now();
    float sumRewards = (float)thrust::reduce(dev_ptr, dev_ptr + blockNum, 0);
    auto deviceEnd2 = std::chrono::high_resolution_clock::now();
    
    root->avgReward = sumRewards / numOfEvaluations;

    timeStamps[0] += (deviceEnd1 - deviceStart1) + (deviceEnd2 - deviceStart2);
    timeStamps[1] += (gpuMemAllocEnd1 - gpuMemAllocStart1) + (gpuMemAllocEnd2 - gpuMemAllocStart2);

    return true;
}

void hostMakeEvaluation(node* root, bool blackEval, int player, std::chrono::nanoseconds* timeStamps)
{
    auto cpuStart = std::chrono::high_resolution_clock::now();
    float sumRewards = 0;
    int baseNumOfWhite = 0;
    int baseNumOfBlack = 0;

    int numOfWhite = 0, numOfBlack = 0;

    for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
        if (root->rows[i] >= 0) baseNumOfWhite++;
    for (int i = PAWN_ROWS * BOARD_SIZE / 2; i < PAWN_ROWS * BOARD_SIZE; i++)
        if (root->rows[i] >= 0) baseNumOfBlack++;

    for (int p = 0; p < (player == PLAYER_ONE ? NUM_OF_EVAL_ONE : NUM_OF_EVAL_TWO); p++)
    {
        node* copyNode = initNode(root->fields, root->rows, root->cols, root->isQueen, root->blackTurn);
        copyNode->lastKill = root->lastKill;
        bool* pawnHasKill = new bool[PAWN_ROWS * BOARD_SIZE];
        bool* available = new bool[BOARD_SIZE * BOARD_SIZE];
        bool blackTurn = copyNode->blackTurn;

        numOfWhite = baseNumOfWhite;
        numOfBlack = baseNumOfBlack;

        if (copyNode->lastKill >= 0)
        {
            h_makeRandomAvailableMove(copyNode->fields, copyNode->rows, copyNode->cols, pawnHasKill, copyNode->isQueen,
                blackTurn, available, numOfWhite, numOfBlack, copyNode->lastKill);
        }
        for (int i = 0; i < MAX_MOVES; i++)
        {
            if (!h_makeRandomAvailableMove(copyNode->fields, copyNode->rows, copyNode->cols, pawnHasKill, copyNode->isQueen,
                blackTurn, available, numOfWhite, numOfBlack)) break;
            blackTurn = !blackTurn;
        }
        if (numOfWhite != numOfBlack)
            sumRewards += evaluatePositionValue(copyNode->rows, copyNode->cols, copyNode->isQueen, blackEval);
        freeNode(copyNode);
        delete[] pawnHasKill;
        delete[] available;
    }
    root->avgReward = sumRewards / (float)(player == PLAYER_ONE ? NUM_OF_EVAL_ONE : NUM_OF_EVAL_TWO);
    auto cpuEnd = std::chrono::high_resolution_clock::now();
    timeStamps[2] += cpuEnd - cpuStart;
}

bool makeMCTSMove(int* fields, int* rows, int* cols, bool* isQueen, bool blackTurn, int player, std::chrono::nanoseconds* timeStamps)
{
    node* root = initNode(fields, rows, cols, isQueen, blackTurn);
    root->parent = nullptr;
    expandNode(root);

    if (root->childSize == 0)
        return false;


    timeStamps[0] = std::chrono::nanoseconds(0);
    timeStamps[1] = std::chrono::nanoseconds(0);
    timeStamps[2] = std::chrono::nanoseconds(0);

    auto gpuMemAllocStart = std::chrono::high_resolution_clock::now();
    float* d_rewards = nullptr;
    fixedNode* d_fixed;
    if (player == PLAYER_ONE && PARALLEL_PLAYER_ONE)
    {
        d_initMemory(&d_rewards, &d_fixed, BLOCK_NUM_ONE);
    }
    else if (player == PLAYER_TWO && PARALLEL_PLAYER_TWO)
    {
        d_initMemory(&d_rewards, &d_fixed, BLOCK_NUM_TWO);
    }
    auto gpuMemAllocEnd = std::chrono::high_resolution_clock::now();
    timeStamps[1] = gpuMemAllocEnd - gpuMemAllocStart;

    for (int p = 0; p < (player == PLAYER_ONE ? TREE_ITER_ONE : TREE_ITER_TWO); p++)
    {

        node* selectedChild = root;
        do {
            float maxUCB = getUCBValue(selectedChild, selectedChild->childs[0]);
            int idxWithBiggestUCB = 0;
            float handlerUCB = 0;
            for (int i = 1; i < selectedChild->childSize; i++)
                if ((handlerUCB = getUCBValue(selectedChild, selectedChild->childs[i])) > maxUCB)
                {
                    maxUCB = handlerUCB;
                    idxWithBiggestUCB = i;
                }
            selectedChild = selectedChild->childs[idxWithBiggestUCB];
        } while (selectedChild->childSize != 0);

        if (selectedChild->howManyVisits == 0)
        {
            if ((player == PLAYER_ONE && !PARALLEL_PLAYER_ONE) || (player == PLAYER_TWO && !PARALLEL_PLAYER_TWO))
                hostMakeEvaluation(selectedChild, blackTurn, player, timeStamps);
            else
                if (!deviceMakeEvaluation(selectedChild, blackTurn, player, d_rewards, d_fixed, timeStamps)) break;

            node* prev = selectedChild->parent;
            while (prev != nullptr)
            {
                prev->avgReward = 0;
                for (int i = 0; i < prev->childSize; i++)
                    prev->avgReward += prev->childs[i]->avgReward;
                prev->avgReward /= prev->childSize;
                prev->howManyVisits = prev->howManyVisits + 1;
                prev = prev->parent;
            }
        }
        else
        {
            expandNode(selectedChild);
        }
        selectedChild->howManyVisits = selectedChild->howManyVisits + 1;
    }

    node* selectedMove = root;
    do {
        float resultReward = selectedMove->childs[0]->avgReward;
        float resultHandler = 0;
        int resultIdx = 0;

        for (int i = 1; i < selectedMove->childSize; i++)
            if ((resultHandler = selectedMove->childs[i]->avgReward) > resultReward)
            {
                resultReward = resultHandler;
                resultIdx = i;
            }

        selectedMove = selectedMove->childs[resultIdx];
    } while (selectedMove->lastKill >= 0 && selectedMove->childSize > 0);

    // this shouldn't ever happen if tree is at least with few levels
    if (selectedMove->lastKill >= 0)
    {
        bool* pawnHasKill = new bool[PAWN_ROWS * BOARD_SIZE];
        bool* available = new bool[BOARD_SIZE * BOARD_SIZE];
        bool* isQueen = new bool[PAWN_ROWS * BOARD_SIZE];
        int numOfWhite = 0, numOfBlack = 0;
        for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
            if (selectedMove->rows[i] >= 0) numOfWhite++;
        for (int i = PAWN_ROWS * BOARD_SIZE / 2; i < PAWN_ROWS * BOARD_SIZE; i++)
            if (selectedMove->rows[i] >= 0) numOfBlack++;
        h_makeRandomAvailableMove(selectedMove->fields, selectedMove->rows, selectedMove->cols, pawnHasKill, isQueen, selectedMove->blackTurn, available, numOfWhite, numOfBlack, selectedMove->lastKill);
        delete[] pawnHasKill;
        delete[] available;
        delete[] isQueen;
    }
    for (int i = 0; i < BOARD_SIZE * BOARD_SIZE; i++)
    {
        fields[i] = selectedMove->fields[i];
    }
    for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
    {
        rows[i] = selectedMove->rows[i];
        cols[i] = selectedMove->cols[i];
        isQueen[i] = selectedMove->isQueen[i];
    }
    d_freeMemory(d_rewards, d_fixed);
    freeNode(root);

    return true;
}

void printOutTimes(std::chrono::nanoseconds* timeStamps, int blackTurn)
{
    string outputFile = "output.txt";
    ofstream output;
    output.open(outputFile, ios::app);

    auto deviceTime = std::chrono::duration_cast<std::chrono::microseconds>(timeStamps[0]).count();
    auto deviceMemoryTime = std::chrono::duration_cast<std::chrono::microseconds>(timeStamps[1]).count();
    auto cpuTime = std::chrono::duration_cast<std::chrono::microseconds>(timeStamps[2]).count();

    output << blackTurn << " " << MAX_MOVES << " "
        << TREE_ITER_ONE << " " << TREE_ITER_TWO << " "
        << NUM_OF_EVAL_ONE << " " << NUM_OF_EVAL_TWO << " "
        << deviceTime << " " << deviceMemoryTime << " " << cpuTime << endl;
    output.close();
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
    unsigned t = time(NULL);
    srand(t);
    std::chrono::nanoseconds timeStamps[3];
    // 0 is for device time
    // 1 is for device memory operations
    // 2 is for cpu time

    window.setFramerateLimit(25);
    Event event;
    int numOfAvailable = 0;
    bool isThereKill = false;

    while (true)
    {
        window.clear(Color::Black);
        window.pollEvent(event);
        if (event.type == Event::Closed)
        {
            window.close();
            break;
        }

        if (PLAYER_VS_AI == 1)
        {
            if (blackTurn)
            {

                if (!makeMCTSMove(fields, rows, cols, isQueen, blackTurn, PLAYER_TWO, timeStamps)) break;
                printOutTimes(timeStamps, blackTurn);
                blackTurn = !blackTurn;
                for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
                {
                    if (rows[i] >= 0)
                    {
                        setPawnPosition(pawns[i], rows[i], cols[i]);
                        pawns[i].setRadius(PAWN_SIZE / 2);
                    }
                    else
                        pawns[i].setRadius(0);
                    if (isQueen[i]) markQueen(pawns, i);
                }
                isThereKill = false;
                for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
                {
                    pawnHasKill[i] = rows[i] >= 0 && (isQueen[i] ? hasQueenKill(fields, rows[i],
                        cols[i], i) : hasKill(fields, i, rows, cols));
                    if (pawnHasKill[i])
                    {
                        isThereKill = true;
                    }
                }
            }
            else if (event.type == Event::MouseButtonPressed)
            {

                if (!blackTurn)
                {
                    performedOperation = false;
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
                    }
                }
                event.type = Event::MouseButtonReleased;
            }
        }
        else if (PLAYER_VS_AI == 0)
        {
            if (!makeMCTSMove(fields, rows, cols, isQueen, blackTurn, blackTurn ? PLAYER_TWO : PLAYER_ONE, timeStamps)) break;
            printOutTimes(timeStamps, blackTurn);
            Time t = sf::seconds(1);
            sleep(t);
            blackTurn = !blackTurn;
            for (int i = 0; i < PAWN_ROWS * BOARD_SIZE; i++)
            {
                if (rows[i] >= 0)
                {
                    setPawnPosition(pawns[i], rows[i], cols[i]);
                    pawns[i].setRadius(PAWN_SIZE / 2);
                }
                else
                    pawns[i].setRadius(0);
                if (isQueen[i]) markQueen(pawns, i);
            }
            isThereKill = false;
            for (int i = 0; i < PAWN_ROWS * BOARD_SIZE / 2; i++)
            {
                pawnHasKill[i] = rows[i] >= 0 && (isQueen[i] ? hasQueenKill(fields, rows[i],
                    cols[i], i) : hasKill(fields, i, rows, cols));
                if (pawnHasKill[i])
                {
                    isThereKill = true;
                }
            }
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

